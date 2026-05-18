package com.aegis.aegis_mobile

import android.os.Bundle
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.FlutterInjector
import com.google.ai.edge.litertlm.*
import org.tensorflow.lite.Interpreter
import java.io.File
import java.lang.StringBuilder
import java.util.concurrent.locks.ReentrantLock

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.aegis.health/litert"
    private var engine: Engine? = null
    private var embeddingInterpreter: Interpreter? = null
    private val inferenceLock = ReentrantLock()

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "loadModels" -> {
                    val gemmaPath = call.argument<String>("gemmaPath")
                    val qwenPath = call.argument<String>("qwenPath")
                    val isExternal = call.argument<Boolean>("isExternal") ?: false
                    
                    Thread {
                        try {
                            val gemmaFile: File
                            val qwenFile: File

                            if (isExternal) {
                                // Models downloaded to persistent storage
                                gemmaFile = File(gemmaPath!!)
                                qwenFile = File(qwenPath!!)
                            } else {
                                // Fallback: Extract from assets if provided
                                val flutterLoader = FlutterInjector.instance().flutterLoader()
                                gemmaFile = File(applicationContext.filesDir, "gemma.litertlm")
                                if (!gemmaFile.exists()) {
                                    val assetKey = flutterLoader.getLookupKeyForAsset(gemmaPath!!)
                                    applicationContext.assets.open(assetKey).use { input ->
                                        gemmaFile.outputStream().use { output -> input.copyTo(output) }
                                    }
                                }
                                qwenFile = File(applicationContext.filesDir, "bert.tflite")
                                if (!qwenFile.exists()) {
                                    val assetKey = flutterLoader.getLookupKeyForAsset(qwenPath!!)
                                    applicationContext.assets.open(assetKey).use { input ->
                                        qwenFile.outputStream().use { output -> input.copyTo(output) }
                                    }
                                }
                            }

                            // Automatic emulator detection to prevent OpenGL backend crashes
                            val isEmulator = (Build.BRAND.startsWith("generic") && Build.DEVICE.startsWith("generic"))
                                    || Build.FINGERPRINT.startsWith("generic")
                                    || Build.FINGERPRINT.startsWith("unknown")
                                    || Build.HARDWARE.contains("goldfish")
                                    || Build.HARDWARE.contains("ranchu")
                                    || Build.MODEL.contains("google_sdk")
                                    || Build.MODEL.contains("Emulator")
                                    || Build.MODEL.contains("Android SDK built for x86")
                                    || Build.MANUFACTURER.contains("Genymotion")
                                    || Build.PRODUCT.contains("sdk_google")
                                    || Build.PRODUCT.contains("google_sdk")
                                    || Build.PRODUCT.contains("sdk")
                                    || Build.PRODUCT.contains("sdk_x86")
                                    || Build.PRODUCT.contains("vbox86p")
                                    || Build.PRODUCT.contains("emulator")
                                    || Build.PRODUCT.contains("simulator")

                            // 1. Initialize LiteRT-LM Engine (Production High-Performance Stack)
                            val config = EngineConfig(
                                modelPath = gemmaFile.absolutePath,
                                backend = if (isEmulator) Backend.CPU() else Backend.GPU(),
                                maxNumTokens = 4096,
                                cacheDir = applicationContext.cacheDir.path
                            )
                            
                            engine = Engine(config).apply {
                                initialize()
                            }

                            // 2. Initialize Embeddings Interpreter (CPU constraint for stability on emulator)
                            val interpreterOptions = Interpreter.Options()
                            interpreterOptions.setNumThreads(4)
                            interpreterOptions.setUseXNNPACK(true)

                            embeddingInterpreter = Interpreter(qwenFile, interpreterOptions)

                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("LOAD_FAILED", "Model Init Failed: ${e.message}", null) }
                        }
                    }.start()
                }
                "generate" -> {
                    val prompt = call.argument<String>("prompt") ?: ""
                    val system = call.argument<String>("system")
                    val currentEngine = engine
                    if (currentEngine == null) {
                        result.error("NOT_LOADED", "Engine not ready", null)
                        return@setMethodCallHandler
                    }

                    val fullPrompt = if (system != null) "System: $system\n\nUser: $prompt\n\nAssistant:" else "User: $prompt\n\nAssistant:"

                    Thread {
                        inferenceLock.lock()
                        try {
                            // LiteRT-LM uses the Conversation pattern for performance
                            val conversation = currentEngine.createConversation()
                            val responseMessage = conversation.sendMessage(fullPrompt)
                            
                            // Robust extraction using toString() to pass back to Flutter
                            val responseText = responseMessage.toString()
                            
                            conversation.close()
                            
                            runOnUiThread { result.success(responseText) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("GENERATE_FAILED", e.message, null) }
                        } finally {
                            inferenceLock.unlock()
                        }
                    }.start()
                }
                "embed" -> {
                    val text = call.argument<String>("text") ?: ""
                    val currentInterpreter = embeddingInterpreter
                    if (currentInterpreter == null) {
                        result.error("NOT_LOADED", "Interpreter not ready", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        inferenceLock.lock()
                        try {
                            val input = arrayOf(text)
                            // Retrieve dynamic output dimension based on the loaded model
                            val outputTensor = currentInterpreter.getOutputTensor(0)
                            val outputDim = outputTensor.shape()[1] // Assuming [1, hidden_size]
                            
                            val output = Array(1) { FloatArray(outputDim) } 
                            currentInterpreter.run(input, output)
                            val list = output[0].toList()
                            runOnUiThread { result.success(list) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("EMBED_FAILED", e.message, null) }
                        } finally {
                            inferenceLock.unlock()
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        engine?.close()
        embeddingInterpreter?.close()
        super.onDestroy()
    }
}
