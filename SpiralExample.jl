
module SpiralExample

using Flux
using DiffEqFlux
using DifferentialEquations
using Random
using Distributions

const noise_std = 0.1 # standard deviation of random noise added to samples
const noise_logvar = 2*log(noise_std)

# The elements of `SpiralSample`s are vectors with two entries for the two dimensions.
const SpiralSample = Vector{Vector{Float64}}

logp_x_z(x, z) = sum(log_normal_pdf(x, z, noise_logvar))

function spiral_clockwise(; start, stop, ntotal, a, b)
    zs = stop .+ 1. .- range(start, length = ntotal, stop=stop)
    rs = a .+ (b .* zs)
    xs = rs .* cos.(zs) .- 5.
    ys = rs .* sin.(zs)
    hcat(xs, ys)
end


function spiral_counterclockwise(; start, stop, ntotal, a, b)
    zs = range(start, length = ntotal, stop = stop)
    rw = a .+ (b .* 20 ./ zs)
    xs = rw .* cos.(zs) .+ 5.
    ys = rw .* sin.(zs)
    hcat(xs, ys)
end


function spiral_samples(; 
        nspiral::Int = 1000, # no of spirals generated
        ntotal::Int = 500, # no of trajectory points for each spiral
        nsample::Int = 100, # no of samples drawn from each spiral
        start::Float64 = 0.0, # spiral starting phi value
        stop::Float64 = 6*pi, # spiral ending phi value
        a::Float64 = 0.0, # parameters defining shape of Archimedean spiral
        b::Float64 = 1.0)
    # Parametric formula for 2d spiral is `r = a + b * phi`.

    # returns named tuple: 
    # - orig_trajs: vector of `SpiralSample`s over a full spiral
    # - samp_trajs: noisy observations, vector of `SpiralSample`s
    # - orig_ts: vector of length `ntotal` containing the timepoints for `orig_trajs`
    # - orig_ts: vector of length `nsample` containing the timepoints for `samp_trajs`

    orig_traj_cc = spiral_counterclockwise(start = start, stop = stop, ntotal = ntotal, a = a, b = b)
    orig_traj_cw = spiral_clockwise(start = start, stop = stop, ntotal = ntotal, a = a, b = b)
    
    # sample starting timestamps
    orig_ts = range(start, length = ntotal, stop = stop)
    samp_ts = orig_ts[1:nsample]
    
    orig_trajs = []
    samp_trajs = []

    for _ in 1:nspiral
        # don't sample t0 very near the start or the end
        pvec = [1. ./ (ntotal.- 4. .* nsample) for _ in 1:(ntotal .- (4 .* nsample))]
        t0_idx = rand(Multinomial(1, pvec))
        t0_idx = argmax(t0_idx) + nsample

        cc = rand() > .5 # uniformly select rotation
        orig_traj = cc ? orig_traj_cc : orig_traj_cw
        push!(orig_trajs, orig_traj)

        samp_traj = deepcopy(orig_traj[t0_idx:2:(t0_idx + 2*(nsample-1)),:])
        samp_traj += randn(size(samp_traj)) .* noise_std
        push!(samp_trajs, samp_traj)
    end

    datatrafo(x) = [[x[i][j,:] for j in 1:size(x[1],1)] for i in 1:length(x)]

    return (orig_trajs = datatrafo(orig_trajs), 
            samp_trajs = datatrafo(samp_trajs), 
            orig_ts = orig_ts, samp_ts = samp_ts)
end


struct LatentTimeSeriesVAE
    rnn
    latentODEfunc
    decoder
end

function LatentTimeSeriesVAE(; latent_dim, obs_dim, rnn_nhidden, f_nhidden, dec_nhidden)
    rnn = Chain(RNN(obs_dim, rnn_nhidden), Dense(rnn_nhidden, latent_dim*2))
    
    latentODEfunc = Chain(Dense(latent_dim, f_nhidden, Flux.elu),
                          Dense(f_nhidden, f_nhidden, Flux.elu),
                          Dense(f_nhidden, latent_dim))

    decoder = Chain(Dense(latent_dim, dec_nhidden, Flux.relu), 
                    Dense(dec_nhidden, obs_dim))
    LatentTimeSeriesVAE(rnn, latentODEfunc, decoder)
end


function paramdict(model)
    Dict("rnn" => Flux.params(model.rnn), 
        "latentODEfunc" => Flux.params(model.latentODEfunc),
        "decoder" => Flux.params(model.decoder))
end


function loadmodel!(model, paramdict::Dict)
    Flux.loadparams!(model.rnn, paramdict["rnn"])
    Flux.loadparams!(model.latentODEfunc, paramdict["latentODEfunc"])
    Flux.loadparams!(model.decoder, paramdict["decoder"])
    model
end


latentz0(μ, logσ) = μ .+ exp.(logσ) .* randn(Float32)

function n_ode(model, z0, t) 
    tspan = (t[1], t[end])
    neural_ode(model.latentODEfunc, z0, tspan, Tsit5(),
            saveat = t, reltol = 1e-7, abstol = 1e-9)
end

function latent_mu_logsd(model, x::Vector{Vector{Float64}}) 
    latent_dim = nhiddennodes(model.latentODEfunc)
    rnn_encoded = rnn_encode(model, x)[end]
    μ = rnn_encoded[1:latent_dim]
    logσ = rnn_encoded[(latent_dim+1):end]
    μ, logσ
end

function rnn_encode(model, x)
    y = reverse(x, dims=1)
    model.rnn.(y)
end

# p(x,z)
function log_normal_pdf(x,mean,logvar)
    constant = log(2*pi)
    -0.5*(constant .+ logvar .+ ((x.-mean).^2 ./ exp.(logvar)))
end


# Kullback-Leibler-divergence
kl_q_p(μ, logσ) = 0.5 * sum(exp.(2 .* logσ) + μ.^2 .- 1 .- (2 .* logσ))

nhiddennodes(d::Dense) = size(d.W, 1)
nhiddennodes(c::Chain) = nhiddennodes(c.layers[end])


# loss function - ELBO
function elbo(model::LatentTimeSeriesVAE, x::SpiralSample, t)
    empmu, emplogsd = latent_mu_logsd(model, x)
    Flux.reset!(model.rnn)
    z0 = latentz0(empmu, emplogsd)
    pred_z = n_ode(model, z0, t)
    sumlogp_x_z = sum([logp_x_z(x[i], model.decoder(pred_z[:,i])) for i in 1:size(pred_z,2)])
    sumlogp_x_z - kl_q_p(empmu, emplogsd)
end



function train!(model::LatentTimeSeriesVAE, xs::Vector{SpiralSample}, t; 
        epochs = 20, learningrate = 0.01, monitoring = (args...) -> nothing)

    opt = ADAM(learningrate)
    zipdata = zip(xs)
    ps = Flux.params(model.rnn, model.latentODEfunc, model.decoder)

    cumloss = 0.0f0
    function loss(x) 
        ret = -elbo(model, x, t) + 0.01 * sum(x->sum(x.^2), Flux.params(model.rnn))
        cumloss += Tracker.data(ret)
        ret
    end

    for epoch in 1:epochs
        Flux.train!(loss, ps, zipdata, opt)
        monitoring(epoch, cumloss)
        cumloss = 0.0f0
    end
end

function predictspiral(model, x::SpiralSample, t)
    predμ, predlogσ = latent_mu_logsd(model, x)
    predz0 = latentz0(predμ, predlogσ)
    predz = n_ode(model, predz0, t)
    predx = [model.decoder(predz[:,i]).data for i in 1:size(predz,2)]
end

end # module SpiralExample