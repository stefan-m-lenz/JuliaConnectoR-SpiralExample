import Pkg
Pkg.activate(".")
Pkg.instantiate()
include("SpiralExample.jl")

spiraldata = SpiralExample.spiral_samples(nspiral = 100,
                                           ntotal = 150,
                                           nsample = 30,
                                           start = 0.0,
                                           stop = 6*pi,
                                           a = 0.0, b = 1.0)


model = SpiralExample.LatentTimeSeriesVAE(latent_dim = 4,
                                           obs_dim = 2,
                                           rnn_nhidden = 25,
                                           f_nhidden = 20,
                                           dec_nhidden = 20)
epochs = 1
SpiralExample.train!(model, spiraldata.samp_trajs, spiraldata.samp_ts,
      epochs = epochs, learningrate = 0.01)