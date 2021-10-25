install.packages("JuliaConnectoR")

library(JuliaConnectoR)

# The results shown in the paper were obtained using Julia 1.4 with
# Flux 0.8.3, DiffEqFlux 0.7.0, DifferentialEquations 6.9.0 and Distributions 0.32.2.
# The next few lines ensure that the correct Julia packages are installed by
# employing a clearly defined Julia project environment
# (see https://pkgdocs.julialang.org/v1.4/environments/).
# Using both the exact Julia version and the exact packages in the Manifest.toml
# permits an exact reproducibility.
# As the random number generator may be subject change in future Julia versions,
# the results may vary slightly when using newer Julia versions.
juliaCall("cd", getwd())
Pkg <- juliaImport("Pkg")
# Use packages specified in Manifest.toml
if (juliaEval('VERSION < v"1.4"')) {
  Pkg$activate("project_1_4") # project environment for Julia 1.4
} else {
  Pkg$activate("project_1_6") # project environment for Julia 1.5 and 1.6
}
# Check whether these packages are installed and install them if not.
# (This may take some time.)
Pkg$instantiate()

# Load module encapsulating the Julia code
# (Recommended pattern)
# Due to the many dependencies, loading the module
# for the first time takes also some time.
juliaCall("include", normalizePath("SpiralExample.jl"))
SpiralExample <- juliaImport(".SpiralExample")


# Inspect ground truth of spirals
ntotal <- 150L
spiral_start <- 0
spiral_stop <- 6*pi
spiral_a <- 0
spiral_b <- 1
spiral_ccw <- SpiralExample$spiral_counterclockwise(start = spiral_start,
                                                    stop = spiral_stop,
                                                    a = spiral_a,
                                                    b = spiral_b,
                                                    ntotal = ntotal)
spiral_cw <- SpiralExample$spiral_clockwise(start = spiral_start,
                                            stop = spiral_stop,
                                            a = spiral_a, b = spiral_b,
                                            ntotal = ntotal)

plot(spiral_cw[,1], spiral_cw[,2], type = "l")
plot(spiral_ccw[,1], spiral_ccw[,2], type = "l")

# Generate spiral samples
juliaEval("using Random; Random.seed!(11);")
spiraldata <- SpiralExample$spiral_samples(nspiral = 100L,
                                           ntotal = 150L,
                                           nsample = 30L,
                                           start = 0,
                                           stop = 6*pi,
                                           a = 0, b = 1)
# (The original paper uses more time points and more spirals.
# This yields better results but needs, of course,
# much more time to train.)

juliaEval("using Random; Random.seed!(11);")

# Define model architecture and initialize model
model <- SpiralExample$LatentTimeSeriesVAE(latent_dim = 4L,
                                           obs_dim = 2L,
                                           rnn_nhidden = 25L,
                                           f_nhidden = 20L,
                                           dec_nhidden = 20L)



# Define a function which can plot the loss during training
epochs <- 20
plotValVsEpoch <- function(epoch, val) {
   if (epoch == 1) {
      ymax <- max(val)
      plot(x = 1, y = val,
           xlim = c(0, epochs), ylim = c(0, ymax*1.1),
           xlab = "Epoch", ylab = "Value")
   } else {
      points(x = epoch, y = val)
   }
}

# Start training (takes some time, the progress can be seen in the plot)
system.time(
   SpiralExample$`train!`(model, spiraldata$samp_trajs, spiraldata$samp_ts,
                          epochs = epochs, learningrate = 0.01,
                          monitoring = plotValVsEpoch)
)

# Due to the complexity of the model, saving and loading the model is
# performed by saving via extracting the parameters and saving it with JLD
# When trying out constellations that train longer, it would also be possible
# to save during the training via calling saveModel() during the monitoring callback.
JLD <- juliaImport("JLD")
saveModel <- function(file = "model.jld") {
   JLD$save(file, "model",
            SpiralExample$paramdict(model))
}

saveModel()

# The model can be loaded at a later time
loadModel <- function(file = "model.jld") {
   juliaEval("using Flux") # to help JLD with recognizing the types
   SpiralExample$`loadmodel!`(model, JLD$load(file, "model"))
}


sampleColor <- "green"
predColor <- "blue"

# Prediction
plotPrediction <- function(ind) {
   predlength <- length(spiraldata$samp_ts) + 10
   sample <- juliaGet(spiraldata$samp_trajs[[ind]])
   predicted <- juliaGet(SpiralExample$predictspiral(model, sample,
                                                     spiraldata$orig_ts[1:predlength]))
   predicted <- Reduce(rbind, predicted, init = c())
   samplemat <- Reduce(rbind, sample, init = c())
   points(x = samplemat[, 1], samplemat[,2], col = sampleColor)
   points(x = predicted[, 1], y = predicted[, 2], col = predColor)
}


# Create plot
# pdf(file="spiralplot.pdf",
#     width=8,
#     height=4.5,
#     pointsize=12)
par(mfrow=c(1,2))
juliaEval("using Random; Random.seed!(11);")
plot(spiral_cw[,1], spiral_cw[,2], type = "l", xlab = "x1", ylab = "x2", cex.axis = 0.8)
title("Clockwise")
plotPrediction(3)

plot(spiral_ccw[,1], spiral_ccw[,2], type = "l", xlab = "x1", ylab = "x2",
     xlim = c(-4, 10), ylim = c(-5, 10), cex.axis = 0.8)
title("Counter-clockwise")
legend(x= "topright", bty = "o", legend =c("Sample", "Prediction"),
                         col=c(sampleColor, predColor), pch = 1, cex=0.8)
plotPrediction(1)
par(mfrow=c(1,1))
# dev.off()

