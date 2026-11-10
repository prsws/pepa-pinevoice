// arena-probe: find the smallest tensor arena a microWakeWord model needs on the PineVoice.
//
// It loads the model the same way the PineVoice C906 firmware does
// (SDK components/microwakeword/src/mww_streaming_model.cpp): the same 20 ops, a
// 2048-byte variable arena, 20 resource variables, the same input/output checks. It is
// compiled against the SDK's own tflite_micro sources, then binary-searches the arena
// size at which AllocateTensors() and Invoke() both succeed.
//
// Build it on a 64-bit host (scripts/probe-arena.sh does). The C906 is RV64, so pointer
// sizes, and with them the arena bookkeeping, match. A 32-bit build reports smaller numbers.
//
// Usage: probe <model.tflite> [manifest_arena_size]
// Exit: 0 = loads (and, if a manifest size was given, it is big enough),
//       1 = the manifest size is too small, 2 = the model does not load at any size / usage.
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <tensorflow/lite/core/c/common.h>
#include <tensorflow/lite/micro/micro_allocator.h>
#include <tensorflow/lite/micro/micro_interpreter.h>
#include <tensorflow/lite/micro/micro_mutable_op_resolver.h>
#include <tensorflow/lite/micro/micro_resource_variable.h>
#include <tensorflow/lite/schema/schema_generated.h>

static const size_t kVarArena = 2048;   // STREAMING_MODEL_VARIABLE_ARENA_SIZE
static const int kMaxVariables = 20;    // MicroResourceVariables::Create(ma_, 20)
static const int kFeatures = 40;        // PREPROCESSOR_FEATURE_SIZE

static bool register_ops(tflite::MicroMutableOpResolver<20>& r) {
  return r.AddCallOnce() == kTfLiteOk && r.AddVarHandle() == kTfLiteOk && r.AddReshape() == kTfLiteOk &&
         r.AddReadVariable() == kTfLiteOk && r.AddStridedSlice() == kTfLiteOk &&
         r.AddConcatenation() == kTfLiteOk && r.AddAssignVariable() == kTfLiteOk &&
         r.AddConv2D() == kTfLiteOk && r.AddMul() == kTfLiteOk && r.AddAdd() == kTfLiteOk &&
         r.AddMean() == kTfLiteOk && r.AddFullyConnected() == kTfLiteOk && r.AddLogistic() == kTfLiteOk &&
         r.AddQuantize() == kTfLiteOk && r.AddDepthwiseConv2D() == kTfLiteOk &&
         r.AddAveragePool2D() == kTfLiteOk && r.AddMaxPool2D() == kTfLiteOk && r.AddPad() == kTfLiteOk &&
         r.AddPack() == kTfLiteOk && r.AddSplitV() == kTfLiteOk;
}

// Same return codes as StreamingModel::load(); 0 = loaded and invoked.
static int try_load(const uint8_t* model_buf, size_t arena_size, int* stride, size_t* used) {
  static tflite::MicroMutableOpResolver<20> resolver;
  static bool registered = false;
  if (!registered) {
    if (!register_ops(resolver)) return -1;
    registered = true;
  }
  uint8_t* arena = static_cast<uint8_t*>(aligned_alloc(16, (arena_size + 15) / 16 * 16));
  uint8_t* var_arena = static_cast<uint8_t*>(aligned_alloc(16, kVarArena));
  int rc = 0;
  auto* ma = tflite::MicroAllocator::Create(var_arena, kVarArena);
  auto* mrv = tflite::MicroResourceVariables::Create(ma, kMaxVariables);
  const tflite::Model* model = tflite::GetModel(model_buf);
  tflite::MicroInterpreter* interp = nullptr;
  if (model->version() != TFLITE_SCHEMA_VERSION) {
    rc = -2;
  } else {
    interp = new tflite::MicroInterpreter(model, resolver, arena, arena_size, mrv);
    if (interp->AllocateTensors() != kTfLiteOk) {
      rc = -3;
    } else {
      TfLiteTensor* in = interp->input(0);
      TfLiteTensor* out = interp->output(0);
      if (in->dims->size != 3 || in->dims->data[0] != 1 || in->dims->data[2] != kFeatures) rc = -4;
      else if (in->type != kTfLiteInt8) rc = -5;
      else if (out->dims->size != 2 || out->dims->data[0] != 1 || out->dims->data[1] != 1) rc = -6;
      else if (out->type != kTfLiteUInt8) rc = -7;
      else {
        for (int i = 0; i < 3 && rc == 0; i++)  // a few invokes: the streaming state must work too
          if (interp->Invoke() != kTfLiteOk) rc = -8;
        if (stride) *stride = in->dims->data[1];
        if (used) *used = interp->arena_used_bytes();
      }
    }
  }
  delete interp;
  free(arena);
  free(var_arena);
  return rc;
}

int main(int argc, char** argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s <model.tflite> [manifest_arena_size]\n", argv[0]);
    return 2;
  }
  FILE* f = fopen(argv[1], "rb");
  if (!f) { perror(argv[1]); return 2; }
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  rewind(f);
  uint8_t* buf = static_cast<uint8_t*>(aligned_alloc(16, (n + 15) / 16 * 16));
  if (fread(buf, 1, n, f) != static_cast<size_t>(n)) { fprintf(stderr, "read failed\n"); return 2; }
  fclose(f);

  // TFLM prints allocation failures to stderr on every failed attempt; keep the output readable.
  if (!freopen("/dev/null", "w", stderr)) return 2;

  size_t lo = 1024, hi = 1 << 20;
  int stride = 0;
  size_t used = 0;
  if (try_load(buf, hi, nullptr, nullptr) != 0) {
    printf("model %s does not load at %zu bytes either: not an arena problem (wrong ops or I/O format)\n",
           argv[1], hi);
    return 2;
  }
  while (lo < hi) {
    size_t mid = (lo + hi) / 2;
    if (try_load(buf, mid, nullptr, nullptr) == 0) hi = mid; else lo = mid + 1;
  }
  try_load(buf, lo, &stride, &used);
  size_t suggested = (lo * 11 / 10 + 999) / 1000 * 1000;  // +10%, rounded up to 1000
  printf("model:            %s (%ld bytes, %d feature slices per inference)\n", argv[1], n, stride);
  printf("minimum arena:    %zu bytes\n", lo);
  printf("suggested arena:  %zu bytes (minimum + 10%%, rounded up)\n", suggested);
  if (argc > 2) {
    long manifest = atol(argv[2]);
    if (manifest < static_cast<long>(lo)) {
      printf("manifest arena:   %ld bytes -> TOO SMALL: the PineVoice firmware allocates exactly this and the "
             "model will not load\n", manifest);
      return 1;
    }
    printf("manifest arena:   %ld bytes -> OK (%ld bytes spare)\n", manifest, manifest - static_cast<long>(lo));
  }
  return 0;
}
