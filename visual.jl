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

function draw_list(array, text::String, width::Float64)
  pathx = Float64[]
  pathy = Float64[]
  for a in array
    push!(pathx, a.o.x)
    push!(pathy, a.o.y)
  end
  push!(pathx, array[end].d.x)
  push!(pathy, array[end].d.y)
  plot!(pathx, pathy, label=text, linewidth=width)
end

function draw_line(line::Line)
  text = "Bus Line " * string(line.index)
  draw_list(line.line, text, 3.0)
end

function draw_path(path::Path)
  penultimate = nothing::Union{Void,Node}
  name = "Path " * string(path.index)
  if length(path.route.pickup) > 0
    draw_list(path.route.pickup, name * " (pickup)", 1.0)
    penultimate = path.route.pickup[end].d
  end
  if length(path.route.buses) > 0
    draw_list(path.route.buses, name * " (bus)", 1.0)
    penultimate = path.route.buses[end].d
  end
  if path.route.dropoff != nothing
    plot!([penultimate.x, path.route.dropoff,x],
        [penultimate.y, path.route.dropoff.y],
        label=name * " (dropoff)", linewidth = 1)
  end
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
  plot!(demandx, demandy, label="Demand")
end

#= These functions are packaged visualization functions. =#

function visual_line(prob::Problem, index::Int64)
  plot()
  draw_terminals(prob)
  draw_line(prob.comp.lines[index])
  gui()
end

function visual_path(prob::Problem, index::Int64)
  plot()
  draw_terminals(prob)
  draw_path(prob.comp.paths[index])
  gui()
end

function visual_basic(prob::Problem)
  println("hi")
  plot()
  draw_terminals(prob)
  draw_demand(prob)
  for (i, f_l) in enumerate(prob.sol.f)
    if f_l > 0.9
      draw_line(prob.comp.lines[i])
    end
  end
  gui()
end
