An example for using neural ordinary differential equations in R via the [JuliaConnectoR](https://github.com/stefan-m-lenz/JuliaConnectoR)
==================================================================

The code for running the example is split into an R part and a Julia part.

The file [SpiralExample.R](SpiralExample.R) contains the R script that runs the complete example.
This R script loads and uses the Julia code in the module `SpiralExample`, which is contained in the file [SpiralExample.jl](SpiralExample.jl).

The auxiliary files [Manifest.toml](Manifest.toml) and [Project.toml](Project.toml) files contain the information about the exact configuration of the packages that are used for replicating the results.
These files were created by Julia while performing package operations in the active project (see [documentation of Julia environments](https://julialang.github.io/Pkg.jl/v1.6/environments/)).
This project works with Julia 1.6.

On an standard desktop PC with an AMD Ryzen 5 CPU with 3.6 GHz, the execution of the complete script takes approximately 11 minutes, excluding the installation of the necessary packages.
The training of the model takes approximately 20 minutes.
The training progress can be watched in the plot that is drawn during the training.

