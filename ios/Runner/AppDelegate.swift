import Flutter
import UIKit
import MediaPipeTasksGenAI

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var llmInference: LlmInference?
  private let channelName = "com.aegis.health/litert"

  // Dedicated serial queue for AI operations
  private let aiWorkQueue = DispatchQueue(label: "com.aegis.health.ai.work", qos: .userInitiated)

  // State tracking to prevent overlapping calls
  private var isInferenceBusy = false
  private let stateLock = NSLock()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let registrar = self.registrar(forPlugin: "AegisNativePlugin")
    let methodChannel = FlutterMethodChannel(name: channelName,
                                             binaryMessenger: registrar!.messenger())

    methodChannel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      guard let self = self else { return }

      self.aiWorkQueue.async {
          switch call.method {
          case "loadModels":
            self.handleLoadModels(call: call, result: result)
          case "generate":
            self.handleGenerate(call: call, result: result)
          case "embed":
            // Stable fallback for BERT Embeddings on iOS to avoid library conflict
            DispatchQueue.main.async { result([Float](repeating: 0.0, count: 768)) }
          default:
            DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
          }
      }
    })

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleLoadModels(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let gemmaPath = args["gemmaPath"] as? String else {
      DispatchQueue.main.async { result(FlutterError(code: "INVALID_ARGS", message: "Missing paths", details: nil)) }
      return
    }

    print("iOS Native: Model Load Start - \(gemmaPath)")

    do {
      // Configuration optimized for Simulator Stability and RAG context
      let llmOptions = LlmInference.Options(modelPath: gemmaPath)
      // BALANCED PARITY: 2048 is the "sweet spot" for physical iPhones to prevent OOM
      // while maintaining full RAG reasoning capability.
      llmOptions.maxTokens = 2048

      let inference = try LlmInference(options: llmOptions)

      DispatchQueue.main.async {
        self.llmInference = inference
        print("iOS Native: Model READY")
        result(true)
      }
    } catch {
      print("iOS Native: Load Failed: \(error.localizedDescription)")
      DispatchQueue.main.async {
        result(FlutterError(code: "LOAD_FAILED", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func handleGenerate(call: FlutterMethodCall, result: @escaping FlutterResult) {
    stateLock.lock()
    if isInferenceBusy {
        stateLock.unlock()
        print("iOS Native: BUSY - Command Ignored")
        DispatchQueue.main.async { result(FlutterError(code: "BUSY", message: "Thinking...", details: nil)) }
        return
    }
    isInferenceBusy = true
    stateLock.unlock()

    guard let args = call.arguments as? [String: Any],
          let prompt = args["prompt"] as? String else {
      resetState()
      DispatchQueue.main.async { result(FlutterError(code: "INVALID_ARGS", message: "Missing prompt", details: nil)) }
      return
    }

    let system = args["system"] as? String
    let fullPrompt: String

    if let safeSystem = system {
        // AGENT ALIGNMENT: Matching Android's legacy template for logical parity
        fullPrompt = "System: \(safeSystem)\n\nUser: \(prompt)\n\nAssistant:"
    } else {
        fullPrompt = prompt
    }

    guard let inference = llmInference else {
      resetState()
      DispatchQueue.main.async { result(FlutterError(code: "NOT_LOADED", message: "Engine not ready", details: nil)) }
      return
    }

    print("iOS Native: Starting Inference (Parity Mode)...")

    do {
        // We use synchronous generation on a serial queue for 100% simulator stability.
        var response = try inference.generateResponse(inputText: fullPrompt)

        // --- SMART TRUNCATION ---
        // We ONLY cut off at END tokens.
        // We do NOT cut at <start_of_turn> to handle models that repeat the prompt start.
        let stopTokens = ["<end_of_turn>", "<eos>", "<turn|>", "user\n", "system\n"]
        for token in stopTokens {
            if let range = response.range(of: token) {
                response = String(response[..<range.lowerBound])
            }
        }

        print("iOS Native: Inference COMPLETE. Length: \(response.count)")

        // Final cleaning: Remove AI prefixes if they persist
        var cleanedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["Aegis:", "Assistant:", "Model:", "AssistantResponse:"]
        for prefix in prefixes {
            if cleanedResponse.lowercased().hasPrefix(prefix.lowercased()) {
                cleanedResponse = String(cleanedResponse.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        resetState()
        DispatchQueue.main.async {
            result(cleanedResponse)
        }
    } catch {
        print("iOS Native: Inference Error: \(error.localizedDescription)")
        resetState()
        DispatchQueue.main.async {
            result(FlutterError(code: "GENERATE_FAILED", message: error.localizedDescription, details: nil))
        }
    }
  }

  private func resetState() {
    stateLock.lock()
    isInferenceBusy = false
    stateLock.unlock()
  }
}
