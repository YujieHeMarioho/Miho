#include "CStemSeparator.h"
#include "onnxruntime_cxx_api.h"
#include <array>
#include <vector>
#include <string>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <memory>

// Native host for the MIT-licensed StemgenRT-5.8 streaming model. Model source:
// https://github.com/sweetspotsoundsystem/StemgenRT-5.8/blob/main/stemgenrt/streaming.py
// Preserve all eight states, the exact source order and the first-hop delay.
struct MihoSeparator {
    Ort::Env env{ORT_LOGGING_LEVEL_WARNING,"Miho"};
    Ort::SessionOptions options;
    Ort::MemoryInfo memory{Ort::MemoryInfo::CreateCpu(OrtArenaAllocator,OrtMemTypeDefault)};
    Ort::Session session{nullptr};
    std::array<float,256> audio{};
    std::array<float,1024> separated{};
    std::array<std::vector<float>,8> stateA,stateB;
    std::vector<Ort::Value> inputs,outputs;
    bool ready = false;
    std::string error;
    const std::array<const char*,9> inputNames{{"audio_chunk","audio_history","fusion_hidden",
        "spectral_numerator_tail","waveform_tail","attention_keys","attention_values",
        "spec_memory_hidden","waveform_memory_hidden"}};
    const std::array<const char*,9> outputNames{{"separated_chunk","next_audio_history","next_fusion_hidden",
        "next_spectral_numerator_tail","next_waveform_tail","next_attention_keys","next_attention_values",
        "next_spec_memory_hidden","next_waveform_memory_hidden"}};

    explicit MihoSeparator(const char *path) {
        options.SetIntraOpNumThreads(1); options.SetInterOpNumThreads(1);
        options.SetExecutionMode(ExecutionMode::ORT_SEQUENTIAL);
        options.AddConfigEntry("session.intra_op.allow_spinning","0");
        options.AddConfigEntry("session.inter_op.allow_spinning","0");
        options.AddConfigEntry("mlas.disable_kleidiai","1");
        session = Ort::Session(env,path,options);
        const std::array<std::vector<int64_t>,9> shapes{{{1,2,128},{1,2,896},{2,1,1000},
            {1,4,2,128},{1,4,2,128},{1,31,64},{1,31,128},{1,1,500},{1,1,500}}};
        if(session.GetInputCount()!=9 || session.GetOutputCount()!=9) throw std::runtime_error("Unexpected streaming model interface");
        Ort::AllocatorWithDefaultOptions allocator;
        for(size_t i=0;i<9;i++) {
            auto input = session.GetInputNameAllocated(i,allocator);
            auto output = session.GetOutputNameAllocated(i,allocator);
            auto info = session.GetInputTypeInfo(i);
            auto type = info.GetTensorTypeAndShapeInfo();
            auto outputInfo = session.GetOutputTypeInfo(i);
            auto outputType = outputInfo.GetTensorTypeAndShapeInfo();
            const std::vector<int64_t> expectedOutput = i==0 ? std::vector<int64_t>{1,4,2,128} : shapes[i];
            if(std::string(input.get())!=inputNames[i] || std::string(output.get())!=outputNames[i] ||
               type.GetElementType()!=ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT || type.GetShape()!=shapes[i] ||
               outputType.GetElementType()!=ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT || outputType.GetShape()!=expectedOutput)
                throw std::runtime_error("Streaming model names/shapes differ");
        }
        inputs.reserve(9); outputs.reserve(9);
        inputs.emplace_back(Ort::Value::CreateTensor<float>(memory,audio.data(),audio.size(),shapes[0].data(),shapes[0].size()));
        const int64_t outputShape[]{1,4,2,128};
        outputs.emplace_back(Ort::Value::CreateTensor<float>(memory,separated.data(),separated.size(),outputShape,4));
        for(size_t i=0;i<8;i++) {
            size_t n=1;for(auto d:shapes[i+1]) n*=static_cast<size_t>(d);
            stateA[i].resize(n);stateB[i].resize(n);
            inputs.emplace_back(Ort::Value::CreateTensor<float>(memory,stateA[i].data(),n,shapes[i+1].data(),shapes[i+1].size()));
            outputs.emplace_back(Ort::Value::CreateTensor<float>(memory,stateB[i].data(),n,shapes[i+1].data(),shapes[i+1].size()));
        }
    }
    void reset() {
        for(auto &v:stateA)std::fill(v.begin(),v.end(),0);
        for(auto &v:stateB)std::fill(v.begin(),v.end(),0);
        ready=false;error.clear();
    }
    int process(const float *left,const float *right,float *vocals,float *drums,float *bass) {
        try {
            for(size_t i=0;i<128;i++) {
                audio[i]=std::isfinite(left[i])?left[i]:0;
                audio[128+i]=std::isfinite(right[i])?right[i]:0;
            }
            session.Run(Ort::RunOptions{nullptr},inputNames.data(),inputs.data(),9,outputNames.data(),outputs.data(),9);
            for(const auto &output:outputs) {
                const float *values=output.GetTensorData<float>();
                const size_t n=output.GetTensorTypeAndShapeInfo().GetElementCount();
                for(size_t i=0;i<n;i++)if(!std::isfinite(values[i]))throw std::runtime_error("Non-finite model output/state");
            }
            for(size_t i=0;i<128;i++) {
                drums[i]=(separated[i]+separated[128+i])*0.5f;
                bass[i]=(separated[256+i]+separated[384+i])*0.5f;
                vocals[i]=(separated[512+i]+separated[640+i])*0.5f;
            }
            for(size_t i=1;i<9;i++)std::swap(inputs[i],outputs[i]);
            const bool valid=ready;ready=true;
            return valid?1:2;
        } catch(const std::exception &e) { reset();error=e.what();return 0; }
    }
};
extern "C" MihoSeparator *miho_separator_create(const char *path,char *error,size_t capacity) {
    try { return new MihoSeparator(path); }
    catch(const std::exception &e) { if(error&&capacity)std::snprintf(error,capacity,"%s",e.what());return nullptr; }
}
extern "C" void miho_separator_destroy(MihoSeparator *s) { delete s; }
extern "C" void miho_separator_reset(MihoSeparator *s) { if(s)s->reset(); }
extern "C" int miho_separator_process(MihoSeparator *s,const float *l,const float *r,float *v,float *d,float *b) {
    return s?s->process(l,r,v,d,b):0;
}
extern "C" const char *miho_separator_error(MihoSeparator *s) { return s?s->error.c_str():"No separator"; }
