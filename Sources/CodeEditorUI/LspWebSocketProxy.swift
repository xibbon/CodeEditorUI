import Foundation
import Network

@available(iOS 13.0, macOS 10.15, visionOS 1.0, *)
public final class LspWebSocketProxy {
    public enum ProxyError: Error {
        case invalidPort(UInt16)
    }

    private final class ConnectionState {
        let ws: NWConnection
        let tcp: NWConnection
        var tcpBuffer = Data()

        init(ws: NWConnection, tcp: NWConnection) {
            self.ws = ws
            self.tcp = tcp
        }
    }

    private let tcpHost: NWEndpoint.Host
    private let tcpPort: NWEndpoint.Port
    private let wsPort: NWEndpoint.Port
    private let queue = DispatchQueue(label: "CodeEditorUI.LspWebSocketProxy")
    private var listener: NWListener?
    private var activeConnections: [UUID: ConnectionState] = [:]
    private var dumpCounter: Int = 0

    public var enableLogging: Bool = false
    public var maxLogBytes: Int = 2*1024

    public init(tcpHost: String = "127.0.0.1", tcpPort: UInt16 = 6005, wsPort: UInt16 = 6009) throws {
        guard let tcpPort = NWEndpoint.Port(rawValue: tcpPort) else {
            throw ProxyError.invalidPort(tcpPort)
        }
        guard let wsPort = NWEndpoint.Port(rawValue: wsPort) else {
            throw ProxyError.invalidPort(wsPort)
        }
        self.tcpHost = NWEndpoint.Host(tcpHost)
        self.tcpPort = tcpPort
        self.wsPort = wsPort
    }

    public func start() throws {
        if listener != nil {
            return
        }
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true

        let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let listener = try NWListener(using: parameters, on: wsPort)
        listener.newConnectionHandler = { [weak self] wsConn in
            self?.handleWebSocketConnection(wsConn)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        for (_, state) in activeConnections {
            state.ws.cancel()
            state.tcp.cancel()
        }
        activeConnections.removeAll()
    }

    private func handleWebSocketConnection(_ wsConn: NWConnection) {
        let tcpConn = NWConnection(host: tcpHost, port: tcpPort, using: .tcp)
        let id = UUID()
        let state = ConnectionState(ws: wsConn, tcp: tcpConn)
        activeConnections[id] = state

        let cleanup: () -> Void = { [weak self] in
            wsConn.cancel()
            tcpConn.cancel()
            self?.activeConnections.removeValue(forKey: id)
        }

        wsConn.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled:
                cleanup()
            default:
                break
            }
        }
        tcpConn.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled:
                cleanup()
            default:
                break
            }
        }

        wsConn.start(queue: queue)
        tcpConn.start(queue: queue)

        func pumpWebSocket() {
            wsConn.receiveMessage { data, _, _, error in
                if let data, !data.isEmpty {
                    if self.enableLogging {
                        self.log(direction: "WS->TCP", data: data)
                    }
                    let framed = self.wrapLspMessage(data)
                    tcpConn.send(content: framed, completion: .contentProcessed { _ in })
                }
                if error != nil {
                    cleanup()
                    return
                }
                pumpWebSocket()
            }
        }

        func pumpTCP() {
            tcpConn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let data, !data.isEmpty {
                    state.tcpBuffer.append(data)
                    self.drainTcpBuffer(state: state, wsConn: wsConn)
                }
                if isComplete || error != nil {
                    cleanup()
                    return
                }
                pumpTCP()
            }
        }

        pumpWebSocket()
        pumpTCP()
    }

    private func wrapLspMessage(_ data: Data) -> Data {
        let header = "Content-Length: \(data.count)\r\n\r\n"
        var framed = Data(header.utf8)
        framed.append(data)
        return framed
    }

    private func drainTcpBuffer(state: ConnectionState, wsConn: NWConnection) {
        while true {
            guard let headerRange = state.tcpBuffer.range(of: Data([13, 10, 13, 10])) else {
                return
            }
            let headerData = state.tcpBuffer.subdata(in: 0..<headerRange.lowerBound)
            guard let headerText = String(data: headerData, encoding: .utf8) else {
                state.tcpBuffer.removeAll()
                return
            }
            var contentLength: Int?
            for line in headerText.split(separator: "\r\n") {
                if line.lowercased().hasPrefix("content-length:") {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        let value = parts[1].trimmingCharacters(in: .whitespaces)
                        contentLength = Int(value)
                    }
                }
            }
            guard let length = contentLength else {
                state.tcpBuffer.removeAll()
                return
            }
            let bodyStart = headerRange.upperBound
            let totalLength = bodyStart + length
            if state.tcpBuffer.count < totalLength {
                return
            }
            let payload = state.tcpBuffer.subdata(in: bodyStart..<totalLength)
            state.tcpBuffer.removeSubrange(0..<totalLength)

            if enableLogging {
                log(direction: "TCP->WS", data: payload)
            }
            //dumpWebSocketPayload(payload)
            let meta = NWProtocolWebSocket.Metadata(opcode: .text)
            let ctx = NWConnection.ContentContext(identifier: "ws-send", metadata: [meta])
            wsConn.send(content: payload, contentContext: ctx, isComplete: true, completion: .contentProcessed { _ in })
        }
    }

    private func dumpWebSocketPayload(_ data: Data) {
        dumpCounter += 1
        let url = URL(fileURLWithPath: "/tmp/DUMP-\(dumpCounter)")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            if enableLogging {
                print("[LSP][DUMP] Failed to write \(url.path): \(error)")
            }
        }
    }

    private func log(direction: String, data: Data) {
        let prefix = "[LSP][\(direction)] "
        if let text = String(data: data, encoding: .utf8) {
            let truncated = text.prefix(maxLogBytes)
            print(prefix + truncated)
        } else {
            let truncated = data.prefix(maxLogBytes)
            print(prefix + truncated.map { String(format: "%02x", $0) }.joined())
        }
    }
}
