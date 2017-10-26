# visual.jl

using Plots


#= These are basic building blocks of visuals. =#

function draw_terminals(prob::Problem)
  xs = Float64[]
  ys = Float64[]
  for t in prob.data.terminals
    push!(xs, t.x)
    push!(ys, t.y)
  end
  scatter!(xs, ys, label = "Terminals")
end

function draw_line(line::Line)
  pathx = Float64[]
  pathy = Float64[]
  for a in line.line # A set of argcs
    push!(pathx, a.o.x)
    push!(pathy, a.o.y)
  end
  push!(pathx, line.line[end].d.x)
  push!(pathy, line.line[end].d.y)
  plot!(pathx, pathy, label = "Bus Line " * string(line.index), linewidth=3)
end

function draw_demand(prob::Problem)
  # We will flatten the demand over all time to a 2D-plane.
  flat_demand = Dict{Tuple{Int64,Int64},Int64}()
  for i = 1:prob.param.terminal_count
    for j = 1:prob.param.terminal_count
      flat_demand[(i, j)] = 0
    end
  end
  
  for ((origin, destid), value) in prob.data.demands
    flat_demand[origin.id, destid] += value
  end
  
  demandx = Float64[]
  demandy = Float64[]
  for ((oid, did), value) in flat_demand
    if value > 0
      origin = prob.data.locations[oid][1]
      destination = prob.data.locations[did][1]
      push!(demandx, origin.x)
      push!(demandy, origin.y)
      push!(demandx, destination.x)
      push!(demandy, destination.y)
      push!(demandx, Inf)
      push!(demandy, Inf)
    end
  end
  plot!(demandx, demandy)
end

function visual_basic(prob::Problem)
  println("hi")
  plot()
  draw_terminals(prob)
  draw_demand(prob)
  for (i, f_l) in enumerate(prob.sol.f)
    if f_l > 0
      draw_line(prob.comp.lines[i])
    end
  end
  gui()
end
