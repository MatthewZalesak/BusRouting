# pathfinding.jl

# Try statement protects items that cannot be initialized more than once.
try
  pathfinding_init
catch
  
  type NodeWrapper
    n::Node
    arc_children::Array{NodeWrapper}
    cw_children::Array{NodeWrapper}
    follower::Union{Void,NodeWrapper}         # If you stay idle at this location
    tracking::Bool                            # Has this variable been touched?
    rode_pickup::Bool
    dist_pickup::Float64
    dist_bus::Float64
    dist_dropoff::Float64
    caller_pickup::Union{Void,NodeWrapper}
    caller_bus::Union{Void,NodeWrapper}
    caller_dropoff::Union{Void,NodeWrapper}
    
    function NodeWrapper(n::Node)
      return new(n, NodeWrapper[], NodeWrapper[], nothing, false, false, Inf, Inf,
          Inf, nothing, nothing, nothing)
    end
  end
end
pathfinding_init = true


function cleanup(a::Array{NodeWrapper})
  for x = a
    x.tracking = false
    x.dist_pickup, x.dist_bus, x.dist_dropoff = Inf, Inf, Inf
    x.caller_pickup, x.caller_bus, x.caller_dropoff = nothing, nothing, nothing
  end
end

type PathFinder
  prob::Problem
  graph::Array{NodeWrapper}
  lookup::Dict{Node,NodeWrapper}
  
  function PathFinder(prob::Problem)
    graph = Array{NodeWrapper}(length(prob.data.terminals))
    lookup = Dict{Node,NodeWrapper}()
    for (i, n) in enumerate(prob.data.terminals)
      nw = NodeWrapper(n)
      graph[i] = nw
      lookup[n] = nw
    end
    for nw in graph
      for child in prob.data.arc_children[nw.n]
        push!(nw.arc_children, lookup[child])
      end
      for child in prob.data.cw_children[nw.n]
        push!(nw.cw_children, lookup[child])
        if child.id == nw.n.id
          nw.follower = lookup[child]
        end
      end
    end
    
    return new(prob, graph, lookup)
  end
end



function unwrap(n::NodeWrapper, pf::PathFinder)
  pickup = Carway[]
  buses = Arc[]
  dropoff = nothing::Union{Void,Carway}
  independentcost = 0
  
  while true
    if n.dist_dropoff < n.dist_pickup && n.dist_dropoff < n.dist_bus
      parent = n.caller_dropoff
      dropoff = pf.prob.data.carways[(parent.n, n.n)]
      independentcost += pf.prob.data.ridehailcosts[(parent.n.id, n.n.id)]
      n = parent
    elseif n.dist_bus < n.dist_pickup
      parent = n.caller_bus
      push!(buses, pf.prob.data.arcs[(parent.n, n.n)])
      n = parent
    else
      parent = n.caller_pickup
      push!(pickup, pf.prob.data.carways[(parent.n, n.n)])
      independentcost += pf.prob.data.ridehailcosts[(parent.n.id, n.n.id)]
      n = parent
    end
    if n.caller_pickup == nothing && n.caller_bus == nothing && 
        n.caller_dropoff == nothing
      break
    end
  end
  pathroute = PathRoute(reverse(pickup), reverse(buses), dropoff) 
  return pathroute, independentcost 
end

function tracking(n::NodeWrapper, frontier::Array{NodeWrapper})
  if !n.tracking
    n.tracking = true
    push!(frontier, n)
  end
end

function update_nodewrapper_dropoff(n::NodeWrapper, destination::Int64,
    frontier::Array{NodeWrapper}, pf::PathFinder)
  dropoff = route((n.n, destination), pf.prob.data, pf.prob.param)
  
  if dropoff != n.n
    distance = n.dist_bus
    r = pf.prob.data.ridehailcosts[(n.n.id, dropoff.id)]
    t = pf.prob.param.lambda * pf.prob.param.time_resolution * (dropoff.t - n.n.t)
    total = r + t + distance
    
    wrapper = pf.lookup[dropoff]
    if total < min(wrapper.dist_pickup, wrapper.dist_bus, wrapper.dist_dropoff)
      wrapper.dist_dropoff = total
      wrapper.caller_dropoff = n
      tracking(wrapper, frontier)
    end
  end
end

function update_nodewrapper_bus(n::NodeWrapper, frontier::Array{NodeWrapper},
    pf::PathFinder)
  distance = min(n.dist_pickup, n.dist_bus)
  for child in n.arc_children
    #t = pf.prob.param.lambda * pf.prob.data.arcs[(n.n, child.n)].data.time
    t = pf.prob.param.lambda * pf.prob.param.time_resolution * (child.n.t - n.n.t)
    z = pf.prob.data.arcs[(n.n, child.n)].data.dualvalue
    total = t + z + distance
    
    if total < min(child.dist_pickup, child.dist_bus, child.dist_dropoff)
      child.dist_bus = total
      child.caller_bus = n
      tracking(child, frontier)
    end
  end
end

function update_nodewrapper_pickup(n::NodeWrapper, frontier::Array{NodeWrapper},
    pf::PathFinder)
  n.rode_pickup && n.follower == nothing && return
  for child in (n.rode_pickup ? [n.follower] : n.cw_children)
    r = pf.prob.data.ridehailcosts[(n.n.id, child.n.id)]
    t = pf.prob.param.lambda * pf.prob.param.time_resolution * (child.n.t - n.n.t)
    total = r + t + n.dist_pickup
    
    if total < min(child.dist_pickup, child.dist_bus, child.dist_dropoff)
      child.dist_pickup = total
      child.rode_pickup = true # n.n.id == child.n.id ? n.rode_pickup : true
      child.caller_pickup = n
      tracking(child, frontier)
    end
  end
end

function terminal_condition(n::NodeWrapper, destination::Int64)
  return n.n.id == destination && (n.caller_pickup != nothing || 
      n.caller_bus != nothing || n.caller_dropoff != nothing)
end

function dijkstra(pf::PathFinder, origin::Node, destination::Int64)
  frontier = NodeWrapper[]
  explored = NodeWrapper[]
  
  push!(frontier, pf.lookup[origin])
  frontier[1].tracking = true
  frontier[1].dist_pickup = 0
  frontier[1].dist_bus = 0
  
  while true
    n = pop!(frontier)
    push!(explored, n)
    
    if terminal_condition(n, destination)
      pathroute, independentcost = unwrap(n, pf)
      path = Path(pathroute, independentcost, n.n.t - origin.t, 0)
      dualdistance = min(n.dist_pickup, n.dist_bus, n.dist_dropoff)
      cleanup(frontier)
      cleanup(explored)
      return path, dualdistance
    end
    
    if n.dist_pickup <= n.dist_bus
      update_nodewrapper_pickup(n, frontier, pf)
      update_nodewrapper_bus(n, frontier, pf)
    else
      update_nodewrapper_bus(n, frontier, pf)
      update_nodewrapper_dropoff(n, destination, frontier, pf)
    end
    
    sort!(frontier, by = x->min(x.dist_pickup,x.dist_bus,x.dist_dropoff), rev=true)
  end
end

function duplicate_check(pf::PathFinder, path::Path)
  for p in pf.prob.comp.paths
    if path.route == p.route && p != path
      throw(ErrorException("This path was a repeat."))
    end
  end
end

function apply_path(pf::PathFinder, path::Path, o::Node, d::Int64)
  path.index = length(pf.prob.comp.paths) + 1
  push!(pf.prob.comp.paths, path)
  push!(pf.prob.comp.ST[(o, d)], path.index)
  
  for arc in path.route.buses
    push!(pf.prob.comp.lookup_paths[arc], path.index)
  end
  cost = path.independentcost + pf.prob.param.lambda * 
      path.taketime * pf.prob.param.time_resolution
  push!(pf.prob.comp.pathcosts, cost)
  
  duplicate_check(pf, path)
end

function search_path(pf::PathFinder)
  paths = Tuple{Path, Node, Int64, Float64}[]
  for (p, (o, d)) in zip(pf.prob.sol.dualdemand, keys(pf.prob.data.demands))
    pf.prob.data.demands[(o, d)] > 0 || continue
    path, duallength = dijkstra(pf, o, d)
    excess = p - duallength
    if excess > pf.prob.param.epsilon
      push!(paths, (path, o, d, excess))
      sort!(paths, by = x->x[4], rev=true)
      length(paths) > prob.param.batch_path ? pop!(paths) : nothing
    end
  end
  
  for (path, origin, dest, excess) in paths
    apply_path(pf, path, origin, dest)
  end
  
  println("Paths added: ", length(paths))
  return length(paths) > 0
end
