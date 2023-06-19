using Complexity
using Distributions
using DifferentialEquations
using DataFrames
using PlotlyJS
using TimerOutputs
using LinearAlgebra

#= Details of the Mountain-Car Task

    The mountain-car taks has two continous state variables, the position of the car x(k),
    and the velocity of the car, v(k). At the start of each episode, the initial state is
    chosen randomly, uniformly from th allowed ranges: -1.2 <= x <= 0.5, -0.7 <= v <= 0.7.
    The mountain car geography is described by altitude(k) = sin(3x(k)). That action, a(k),
    takes values -1 <= a <= 1. The state evolution is according to the following simplified
    physics:

    v(k+1) = bound[v(k) + 0.001*a(k) - g*cos(3*x(k))]

    and

    x(k+1) = bound[x(k) + v(k+1)]

    where g = -0.0025 is the force of gravity and the bound operation clips each variable
    within its allowed range. If x(k+1) is clipped in this way, then v(k+1) is also reset to
    zero. The episode terminates with the first position value that exceeds x(k+1) > 0.5.

=#

println("...........o0o----ooo0§0ooo~~~  START  ~~~ooo0§0ooo----o0o...........")

#-------------------------------------------------------------------------------------------
# Parameters

T = 100 # horison
J = 200 # episodes

γ = 0.98 # discounting factor

# kernel bandwidth, scale
ζ = 0.5

# actor step size
η = 0.01

σ = 0.03 # standard deviation

# initial condition ranges
x_range = 0.01*[-1.2, 0.5]
v_range = 0.01*[-0.07, 0.07]

# initial actor weights
#actor_Λ = [0]
#actor_C = zeros(2)

#-------------------------------------------------------------------------------------------
# dataframes

sample_hook = DataFrame()
inner_hook = DataFrame()
episode_hook = DataFrame()

#-------------------------------------------------------------------------------------------
# Learning

f = zeros(T)

j = 1
for j in 1:J # episodes

    global x, actor_Λ, actor_C, η, ζ, γ, σ, episode_hook, inner_hook, sample_hook

    # initial conditions

    #x = [rand(Uniform(x_range[1], x_range[2])), rand(Uniform(v_range[1], v_range[2]))]

    x = [-0.5, 0] #+ 0.01*randn(2)

    # policy parameters

    if j < J/2
        #σ = σ/J # standard deviation
    end

    Σ = (σ^2)*Matrix(I,1,1) # covariance matrix
    Σinv = inv(Σ) # for compatible kernel

    for k in 1:T # time steps

        global x, actor_Λ, actor_C, episode_hook, inner_hook, sample_hook

        # mean vector
        μ = function_approximation(x, actor_Λ, actor_C, ζ)

        # Create the multivariate normal distribution
        π_ax = MvNormal([μ], Σ)

        # Generate a random sample from the distribution
        a = clamp.(rand(π_ax), -1, 1)

        reward = exp(-8*(x[1] - 0.6)^2)

        sample_hook = DataFrame(t = k, x = x[1], v = x[2], a = a, μ = μ, r = reward)
        append!(inner_hook, sample_hook)

        if x[1] >= 0.5
            break
        end

        # evolve
        #a = 1.0
        x = Mountain_Car(x, a)

    end

    #σ = 0.01 # standard deviation
    #Σ = (σ^2)*Matrix(I,2,2) # covariance matrix
    #Σinv = inv(Σ) # for compatible kernel

    state_data = @views transpose(Matrix(inner_hook[:,2:3]))
    action_data = @views transpose(inner_hook[:,4])
    mean_data = @views transpose(inner_hook[:,5])
    rewards_data = @views inner_hook[:,6]

    data = @views (state_data, action_data, mean_data)

    α, Q, D, b = KLSTD(data, rewards_data, ζ, Σinv, γ)

    #display(Q)

    if j < J/1
        #η = η/J
    end

    f_μ = SGA(data, ζ, Σinv, η, Q)

    f_μ = clamp.(f_μ, -1, 1)

    actor_Λ, actor_C, err = OMP(data[1], ζ, f_μ; N = 15)

    println("rewards = ", round(1000*sum(rewards_data), digits = 3))
    println("error = ", round(err, digits = 3))
    println("jump = ", maximum(f_μ .- data[3]))
    println("jump Q = ", maximum(Q))
    println("jump Q = ", minimum(Q))
    println("j = ", j)

    if isnan(Q[1])

        display(f_μ)
        display(Gramian(data[1], ζ))
        display(Σinv)

        #break
    else
        empty!(episode_hook)
        append!(episode_hook, inner_hook)
    end
    empty!(inner_hook)

    #= fn = zeros(T)
    for k in 1:T

        fn[k] = function_approximation(data[1][:,k], Λ, C, ζ)
    end =#

    #=
        G1  = Gramian(data[1], ζ)
        G2  = Gramian(data, ζ; kernel = Compatible_kernel, Σinv = Σinv)

        z₁ = (data[1][:,1], data[2][:,1], data[3][:,1])
        z₂ = (data[1][:,5], data[2][:,5], data[3][:,5])

        k1 = Gaussian_kernel(z₁[1], z₂[1], ζ, dims = 2)

        k = Compatible_kernel(z₁, z₂, ζ; kernel = Gaussian_kernel, Σinv = Σinv)
    =#

end

#= ϵ = 1e-6

G = Gramian([data[1]; data[2]], ζ)

T = size(data[1], 2)

D1 = zeros(T, T)
b1 = zeros(T)

for k in 1:T

    global D1, b1, γ

    D1 += G[:,k]*transpose(G[:,k] - γ*G[:,k])
    b1 += G[:,k]*rewards_data[k]

end

b2 = sum(G.*transpose(rewards_data), dims = 2)
D2 = G.*transpose(G - γ*G)

α1 = (D1 + ϵ*I) \ b1 # inv(D1)*b1

Q1 = zeros(T)

for k in 1:T

    Q1[k] = α1[k]*sum(G[k,:])

end

ϑ = Array{Float64,1}(undef, T) # feature vector

dat = [data[1]; data[2]]

for n in 1:T

    ϑ[n] = Gaussian_kernel(dat[:,n], dat[:,1], ζ)

end

Q3 = transpose(α1)*ϑ

Q2 = transpose(α1)*transpose(G) =#


#= #σ = 0.01 # standard deviation
Σ = (σ^2)*Matrix(I,2,2) # covariance matrix
Σinv = inv(Σ) # for compatible kernel

state_data = @views transpose(Matrix(episode_hook[:,2:3]))
action_data = @views transpose(episode_hook[:,4])
mean_data = @views transpose(episode_hook[:,5])
rewards_data = @views episode_hook[:,6]

data = @views (state_data, action_data, mean_data)

α, Q, D, b = KLSTD(data, rewards_data, ζ, Σinv, γ)

f_μ = SGA(data, ζ, Σinv, η, Q; kernel = Gaussian_kernel)

actor_Λ, actor_C, err = OMP(data[1], ζ, f_μ; N = 20) =#

#-------------------------------------------------------------------------------------------
# Plots

traces = [scatter(episode_hook, x = :t, y = :x, name = "position"),
            scatter(episode_hook, x = :t, y = :v, name = "velocity"),
            scatter(episode_hook, x = :t, y = :r, name = "reward"),
            scatter(episode_hook, x = :t, y = :a, name = "actions"),]

plot_episode = plot(traces,
                Layout(
                    title = attr(
                        text = "Episodic State",
                        ),
                    title_x = 0.5,
                    xaxis_title = "t [s]",
                    yaxis_title = "x [m], y [m/s]",
                    ),
                )

display(plot_episode)

println("\n\n...........o0o----ooo0§0ooo~~~   END   ~~~ooo0§0ooo----o0o...........\n")