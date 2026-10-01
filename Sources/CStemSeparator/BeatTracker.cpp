#include "CStemSeparator.h"
#include "BeatFilters.h"
#include "onnxruntime_cxx_api.h"
#include <array>
#include <vector>
#include <complex>
#include <cmath>
#include <string>
#include <algorithm>
#include <cstdio>
#include <stdexcept>

// Exact 1411-point Hann FFT using a Bluestein convolution; no future samples,
// rescaled FFT bins, or 2048-point approximation of the training features.
struct BeatFeatures {
    using Complex=std::complex<double>;
    static constexpr int N=1411, M=4096;
    std::array<Complex,M> kernel{}, work{};
    std::array<Complex,N> chirp{};
    std::array<double,N> window{};
    std::array<float,136> previous{};
    bool hasPrevious=false;
    static void fft(std::array<Complex,M> &a,bool inverse) {
        for(int i=1,j=0;i<M;i++) {
            int bit=M>>1;for(;j&bit;bit>>=1)j^=bit;j^=bit;
            if(i<j)std::swap(a[i],a[j]);
        }
        for(int len=2;len<=M;len<<=1) {
            const auto root=std::polar(1.0,(inverse?2:-2)*std::acos(-1.0)/len);
            for(int i=0;i<M;i+=len) {
                Complex w=1;
                for(int j=0;j<len/2;j++) {
                    const auto u=a[i+j],v=a[i+j+len/2]*w;
                    a[i+j]=u+v;a[i+j+len/2]=u-v;w*=root;
                }
            }
        }
        if(inverse)for(auto &v:a)v/=M;
    }
    BeatFeatures() {
        const double pi=std::acos(-1.0);
        for(int i=0;i<N;i++) {
            chirp[i]=std::polar(1.0,-pi*double(i)*i/N);
            window[i]=0.5-0.5*std::cos(2*pi*i/(N-1));
            kernel[i]=std::conj(chirp[i]);
            if(i)kernel[M-i]=kernel[i];
        }
        fft(kernel,false);
    }
    void reset() { previous.fill(0);hasPrevious=false; }
    void process(const float *audio,float *features) {
        work.fill(0);
        for(int i=0;i<N;i++)work[i]=(std::isfinite(audio[i])?audio[i]:0)*window[i]*chirp[i];
        fft(work,false);for(int i=0;i<M;i++)work[i]*=kernel[i];fft(work,true);
        // madmom stores the complex STFT as float32 before taking magnitudes.
        std::array<float,705> magnitude{};
        for(int i=0;i<705;i++) {
            const auto value=work[i]*chirp[i];
            magnitude[i]=std::abs(std::complex<float>(float(value.real()),float(value.imag())));
        }
        for(int band=0;band<136;band++) {
            const auto &f=beatFilters[band];float sum=0;
            for(int j=0;j<f.count;j++)sum+=magnitude[f.start+j]*f.weights[j];
            const float logarithm=std::log10(1+sum);
            features[band]=logarithm;
            features[136+band]=hasPrevious?std::max(0.0f,logarithm-previous[band]):0;
            previous[band]=logarithm;
        }
        hasPrevious=true;
    }
};
struct MihoBeatTracker {
    Ort::Env env{ORT_LOGGING_LEVEL_WARNING,"MihoBeatNet"};
    Ort::SessionOptions options;
    Ort::MemoryInfo memory{Ort::MemoryInfo::CreateCpu(OrtArenaAllocator,OrtMemTypeDefault)};
    Ort::Session session{nullptr};
    BeatFeatures extractor;
    std::array<float,272> features{};
    std::array<float,3> probabilities{};
    std::array<float,300> h{},c{},nextH{},nextC{};
    std::vector<Ort::Value> inputs,outputs;
    std::string error;
    const std::array<const char*,3> inputNames{{"features","hidden","cell"}};
    const std::array<const char*,3> outputNames{{"probabilities","next_hidden","next_cell"}};
    explicit MihoBeatTracker(const char *path) {
        options.SetIntraOpNumThreads(1);options.SetInterOpNumThreads(1);
        options.SetExecutionMode(ExecutionMode::ORT_SEQUENTIAL);
        options.AddConfigEntry("session.intra_op.allow_spinning","0");
        options.AddConfigEntry("mlas.disable_kleidiai","1");
        session=Ort::Session(env,path,options);
        const std::array<std::vector<int64_t>,3> inShapes{{{1,1,272},{2,1,150},{2,1,150}}};
        const std::array<std::vector<int64_t>,3> outShapes{{{3},{2,1,150},{2,1,150}}};
        if(session.GetInputCount()!=3||session.GetOutputCount()!=3)throw std::runtime_error("Unexpected BeatNet interface");
        Ort::AllocatorWithDefaultOptions allocator;
        for(size_t i=0;i<3;i++) {
            auto name=session.GetInputNameAllocated(i,allocator);auto outName=session.GetOutputNameAllocated(i,allocator);
            auto info=session.GetInputTypeInfo(i);auto type=info.GetTensorTypeAndShapeInfo();
            auto outInfo=session.GetOutputTypeInfo(i);auto outType=outInfo.GetTensorTypeAndShapeInfo();
            if(std::string(name.get())!=inputNames[i]||std::string(outName.get())!=outputNames[i]||
               type.GetShape()!=inShapes[i]||outType.GetShape()!=outShapes[i]||
               type.GetElementType()!=ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT||outType.GetElementType()!=ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT)
                throw std::runtime_error("BeatNet names/shapes differ");
        }
        inputs.reserve(3);outputs.reserve(3);
        inputs.emplace_back(Ort::Value::CreateTensor<float>(memory,features.data(),272,inShapes[0].data(),3));
        inputs.emplace_back(Ort::Value::CreateTensor<float>(memory,h.data(),300,inShapes[1].data(),3));
        inputs.emplace_back(Ort::Value::CreateTensor<float>(memory,c.data(),300,inShapes[2].data(),3));
        outputs.emplace_back(Ort::Value::CreateTensor<float>(memory,probabilities.data(),3,outShapes[0].data(),1));
        outputs.emplace_back(Ort::Value::CreateTensor<float>(memory,nextH.data(),300,outShapes[1].data(),3));
        outputs.emplace_back(Ort::Value::CreateTensor<float>(memory,nextC.data(),300,outShapes[2].data(),3));
    }
    void reset() {
        h.fill(0);c.fill(0);nextH.fill(0);nextC.fill(0);
        extractor.reset();error.clear();
    }
    int process(const float *audio,float *result,float *outFeatures) {
        try {
            extractor.process(audio,features.data());
            session.Run(Ort::RunOptions{nullptr},inputNames.data(),inputs.data(),3,outputNames.data(),outputs.data(),3);
            for(const auto &output:outputs) {
                const auto *values=output.GetTensorData<float>();
                for(size_t i=0;i<output.GetTensorTypeAndShapeInfo().GetElementCount();i++)
                    if(!std::isfinite(values[i]))throw std::runtime_error("Non-finite BeatNet output/state");
            }
            std::copy(probabilities.begin(),probabilities.end(),result);
            if(outFeatures)std::copy(features.begin(),features.end(),outFeatures);
            std::swap(inputs[1],outputs[1]);std::swap(inputs[2],outputs[2]);
            return 1;
        } catch(const std::exception &e) {reset();error=e.what();return 0;}
    }
};
extern "C" MihoBeatTracker *miho_beat_create(const char *path,char *error,size_t n) {
    try{return new MihoBeatTracker(path);}catch(const std::exception &e){if(error&&n)std::snprintf(error,n,"%s",e.what());return nullptr;}
}
extern "C" void miho_beat_destroy(MihoBeatTracker *b){delete b;}
extern "C" void miho_beat_reset(MihoBeatTracker *b){if(b)b->reset();}
extern "C" int miho_beat_process(MihoBeatTracker *b,const float *audio,float *probabilities,float *features){return b?b->process(audio,probabilities,features):0;}
extern "C" const char *miho_beat_error(MihoBeatTracker *b){return b?b->error.c_str():"No beat tracker";}
