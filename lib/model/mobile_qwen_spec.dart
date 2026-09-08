class MobileQwenSpec {
  static const baseModel = 'Qwen2.5-0.5B-Instruct';
  static const ggufRepo = 'Qwen/Qwen2.5-0.5B-Instruct-GGUF';
  static const quant = 'Q4_K_M';
  static const contextSize = 4096;
  static const maxNewTokens = 256;
  static const runtimeContract = 'LLAMA_CPP_GGUF_ADAPTER';
}
