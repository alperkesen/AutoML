using Knet: KnetArray, RNN, Param, relu, sumabs2, mat, conv4, pool, dropout,
    nll, gpu, xavier
using Statistics: mean


struct LinearLayer; w; b; f; pdrop; end

LinearLayer(i::Int, o::Int, f=relu; pdrop=0.5,
            atype=gpu()>=0 ? KnetArray{Float64} : Array{Float64}) = LinearLayer(
                Param(atype(xavier(o, i))), Param(atype(zeros(o))), f, pdrop)

(l::LinearLayer)(x) = l.f.(l.w * mat(dropout(x, l.pdrop)) .+ l.b)
(l::LinearLayer)(x, y) = sumabs2(y - l(x)) / size(y,2)


struct LinearChain
    layers
    LinearChain(layers...) = new(layers)
end

(c::LinearChain)(x) = (for l in c.layers; x = l(x); end; x)
(c::LinearChain)(x, y) = sumabs2(y - c(x)) / size(y,2)

struct CategoricalChain
    layers
    CategoricalChain(layers...) = new(layers)
end

(c::CategoricalChain)(x) = (for l in c.layers; x = l(x); end; x)
(c::CategoricalChain)(x, y) = nll(c(x), y)

struct Conv; w; b; f; pdrop; end

Conv(w1::Int, w2::Int, cx::Int, cy::Int, f=relu; pdrop=0,
     atype=gpu()>=0 ? KnetArray{Float64} : Array{Float64}) =
         Conv(Param(atype(xavier(w1, w2, cx, cy))),
              Param(atype(zeros(1, 1, cy, 1))),
              f,
              pdrop)

(c::Conv)(x) = c.f.(pool(conv4(c.w, dropout(x, c.pdrop)) .+ c.b))


struct OneLayerBiRNN; input; rnn; output; b; pdrop; end

OneLayerBiRNN(input::Int, embed::Int, hidden::Int, output::Int; pdrop=0,
              scale=0.01, atype=gpu()>=0 ? KnetArray{Float64} : Array{Float64},
              rnnType=:gru, bidirectional=false) =
    OneLayerBiRNN(Param(atype(randn(embed, input) * scale)),
                  RNN(embed, hidden, rnnType=rnnType, dataType=Float64,
                      bidirectional=bidirectional),
                  Param(atype(randn(output, hidden) * scale)),
                  Param(atype(zeros(output))),
                  pdrop)

function (c::OneLayerBiRNN)(input)
    embed = c.input[:, permutedims(hcat(input...))]
    embed = dropout(embed, c.pdrop)
    hiddenoutput = c.rnn(embed)
    hiddenoutput = dropout(hiddenoutput, c.pdrop)

    return c.output * hiddenoutput[:,:,end] .+ c.b
end

(c::OneLayerBiRNN)(input,output) = nll(c(input), output)


struct TwoTextsClassifier; input; rnn; output; b; pdrop; end

TwoTextsClassifier(input::Int, embed::Int, hidden::Int, output::Int; pdrop=0,
                   scale=0.01, atype=gpu()>=0 ? KnetArray{Float64} :
                   Array{Float64}, rnnType=:gru, bidirectional=true) =
    TwoTextsClassifier(Param(atype(randn(embed, input) * scale)),
                       RNN(embed, hidden, rnnType=rnnType, dataType=Float64,
                           bidirectional=bidirectional),
                       Param(atype(randn(output, 4hidden) * scale)),
                       Param(atype(zeros(output))),
                       pdrop)

function (c::TwoTextsClassifier)(input)
    input1 = hcat(input...)[1, :]
    input2 = hcat(input...)[2, :]
 
    embed1 = c.input[:, permutedims(hcat(input1...))]
    embed1 = dropout(embed1, c.pdrop)

    embed2 = c.input[:, permutedims(hcat(input1...))]
    embed2 = dropout(embed2, c.pdrop)

    hiddenoutput1 = c.rnn(embed1)
    hiddenoutput2 = c.rnn(embed2)

    H, B, W = size(hiddenoutput1)

    hiddenoutput1 = reshape(hiddenoutput1, H, :)
    hiddenoutput2 = reshape(hiddenoutput2, H, :)

    hiddenoutput = vcat(hiddenoutput1, hiddenoutput2)
    hiddenoutput = reshape(hiddenoutput, 2H, B, W)
    hiddenoutput = sum(hiddenoutput, dims=3)[:, :, end]
    hiddenoutput = dropout(hiddenoutput, c.pdrop)

    return c.output * hiddenoutput .+ c.b
end

(c::TwoTextsClassifier)(input,output) = nll(c(input), output)


struct TwoLayerBiRNN; input; rnn; rnn2; output; b; pdrop; end

TwoLayerBiRNN(input::Int, embed::Int, hidden1::Int, hidden2::Int,
              output::Int; pdrop=0, scale=0.01,
              atype=gpu()>=0 ? KnetArray{Float64} : Array{Float64},
              rnnType=:gru, bidirectional=false) = TwoLayerBiRNN(
                  Param(atype(randn(embed, input) * scale)),
                  RNN(embed, hidden1, rnnType=rnnType, dataType=Float64,
                      bidirectional=bidirectional),
                  RNN(2hidden1, hidden2, rnnType=rnnType, dataType=Float64,
                      bidirectional=bidirectional),
                  Param(atype(randn(output, 2hidden2) * scale)),
                  Param(atype(zeros(output))),
                  pdrop)

function (c::TwoLayerBiRNN)(input)
    embed = c.input[:, permutedims(hcat(input...))]
    embed = dropout(embed, c.pdrop)
    hiddenoutput = c.rnn(embed)
    hiddenoutput = dropout(hiddenoutput, c.pdrop)
    hiddenoutput2 = c.rnn2(hiddenoutput)
    hiddenoutput2 = dropout(hiddenoutput2, c.pdrop)

    return c.output * hiddenoutput2[:,:,end] .+ c.b
end

(c::TwoLayerBiRNN)(input,output) = nll(c(input), output)


predict(model, x) = map(i->i[1], findmax(Array(model(x)),dims=1)[2])
accuracy(model, x, y) = mean(y .== predict(model, x))
accuracy(model, data) = mean(accuracy(model,x,y) for (x,y) in data)
