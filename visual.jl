# visual.jl

using Plots


#= Special functions for visualizing variables. =#

function show(io::IO, n::Node)
  print(io, "Node(L", n.id, ")")
end

function show(io::IO, ad::ArcData)
  print(io, "ArcData(", round(ad.time, 4), ", ", round(ad.dualvalue, 6), ")")
end

function show(io::IO, line::Line)
  print(io, "Line(")
  show(io, line.line)
  print(io, ", cost => ", line.cost)
  print(io, ", ID => ", line.index, ")")
end

function show(io::IO, pr::PathRoute)
  print(io, "PathRoute(pickup=> ")
  print(io, pr.pickup)
  print(io, ", buses=> ")
  for b in pr.buses
    show(io, b)
    print(io, ", ")
  end
  print(io, "dropoff=> ")
  if pr.dropoff != nothing
    show(io, pr.dropoff)
  end
  print(io, ")")
end

function show(io::IO, p::Path)
  print(io, "Path(ID ", p.index, ", ")
  show(io, p.route)
  print(io, ", duration: ", round(p.taketime, 4), ")")
end

function show(io::IO, nw::NodeWrapper)
  print(io, "NodeWrapper(base => ", nw.n)
  print(io, ", pickup dist => ", nw.dist_pickup)
  print(io, ", bus dist => ", nw.dist_bus)
  print(io, ", dropoff dist => ", nw.dist_dropoff, ")")
end

function show(io::IO, pf::PathFinder)
  print(io, "PathFinder(graph size => ", length(pf.graph), ")")
end

function show(io::IO, cnw::ColorNodeWrapper)
  print(io, "ColorNodeWrapper(base => ", cnw.n)
  print(io, ", colors => ", map(x -> sum(map(y -> y[1], values(x))), cnw.colors), "))")
end

function show(io::IO, ca::ColorArc)
  print(io, "ColorArc(<o>, <d>, color => ", ca.color)
  print(io, ", dualvalue => ", round(ca.arc.dualvalue, 10), "))")
end

function show(io::IO, lf::LineFinder)
  print(io, "LineFinder(limit => ", lf.limit, ")")
end


#= These are basic building blocks of visuals. =#

function draw_terminals(prob::Problem)
  xs = [t.x for t in prob.data.terminals]
  ys = [t.y for t in prob.data.terminals]
  scatter!(xs, ys, label = "Terminals")
end

function draw_list(array, text::String, width::Float64)
  pathx = [a.o.x for a in array]::Array{Float64}
  pathy = [a.o.y for a in array]::Array{Float64}
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

function draw_ridehail(prob::Problem)
  arcs = Dict{Tuple{Node,Node},Void}()
  for (y, path) in zip(prob.sol.y, prob.comp.paths)
    if y > 0
      if path.route.pickup != nothing
        arcs[path.route.pickup] = nothing
      end
      if path.route.dropoff != nothing
        arcs[path.route.dropoff] = nothing
      end
    end
  end
  xs = Float64[]
  ys = Float64[]
  for (o, d) in keys(arcs)
    push!(xs, o.x) ; push!(xs, d.x) ; push!(xs, Inf)
    push!(ys, o.y) ; push!(ys, d.y) ; push!(ys, Inf)
  end
  plot!(xs, ys, label="RideHails", linewidth = 2)
end

function draw_demand(prob::Problem)
  # We will flatten the demand over all time to a 2D-plane.
  flat_demand = Dict{Tuple{Int64,Int64},Int64}()
  for i = 1:prob.param.terminal_count
    for j = 1:prob.param.terminal_count
      flat_demand[(i, j)] = 0
    end
  end
  
  demandx = Float64[]
  demandy = Float64[]
  for ((origin, destination), value) in prob.data.demands
    if value > 0
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

function visual_line(prob::Problem, index::Int64, count::Int64)
  plot()
  for i = 1:min(count, length(prob.comp.lines[index].line))
    l = prob.comp.lines[index].line[i]
    plot!([l.o.x, l.d.x], [l.o.y, l.d.y], label=string(i), linewidth=1.0)
  end
  gui()
end

function visual_path(prob::Problem, index::Int64)
  plot()
  draw_terminals(prob)
  draw_path(prob.comp.paths[index])
  gui()
end

function visual_basic(prob::Problem, show_ridehail::Bool)
  plot()
  draw_terminals(prob)
  draw_demand(prob)
  for (i, f_l) in enumerate(prob.sol.f)
    if f_l > 0.9
      draw_line(prob.comp.lines[i])
    end
  end
  show_ridehail && draw_ridehail(prob)
  gui()
end

function visual_basic(prob::Problem)
  return visual_basic(prob, true)
end
