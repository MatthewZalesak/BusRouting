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
    rode_pickup::Bool                         # Can we ride a pickup from here?
    dist_pickup::Float64
    dist_bus::Float64
    dist_dropoff::Float64
    caller_pickup::Union{Void,NodeWrapper}    # 'caller' fields enable backtracking.
    caller_bus::Union{Void,NodeWrapper}
    caller_dropoff::Union{Void,NodeWrapper}
    
    function NodeWrapper(n::Node)
      return new(n, NodeWrapper[], NodeWrapper[], nothing, false, false, Inf, Inf,
          Inf, nothing, nothing, nothing)
    end
  end
  
  using DataStructures # Load just once for convenicen
end
pathfinding_init = true


function cleanup(a::Array{NodeWrapper})
  for x = a
    x.tracking = false
    x.rode_pickup = false
    x.dist_pickup, x.dist_bus, x.dist_dropoff = Inf, Inf, Inf
    x.caller_pickup, x.caller_bus, x.caller_dropoff = nothing, nothing, nothing
  end
end

function cleanup(a::PriorityQueue{NodeWrapper,Float64})
  for x = keys(a)
    x.tracking = false
    x.rode_pickup = false
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

function tracking(n::NodeWrapper, frontier::PriorityQueue{NodeWrapper,Float64},
    value::Float64)
  if !n.tracking
    n.tracking = true
    enqueue!(frontier, n, value)
  else
    frontier[n] = value
  end
end

function update_nodewrapper_dropoff(n::NodeWrapper, destination::Int64,
    frontier::PriorityQueue{NodeWrapper,Float64}, pf::PathFinder)
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
      tracking(wrapper, frontier, total)
    end
  end
end

function update_nodewrapper_bus(n::NodeWrapper,
    frontier::PriorityQueue{NodeWrapper}, pf::PathFinder)
  distance = min(n.dist_pickup, n.dist_bus)
  for child in n.arc_children
    t = pf.prob.param.lambda * pf.prob.param.time_resolution * (child.n.t - n.n.t)
    z = pf.prob.data.arcs[(n.n, child.n)].data.dualvalue
    total = t + z + distance
    
    if total < min(child.dist_pickup, child.dist_bus, child.dist_dropoff)
      child.dist_bus = total
      child.caller_bus = n
      tracking(child, frontier, total)
    end
  end
end

function update_nodewrapper_pickup(n::NodeWrapper,
    frontier::PriorityQueue{NodeWrapper,Float64},  pf::PathFinder)
  n.rode_pickup && n.follower == nothing && return
  for child in (n.rode_pickup ? [n.follower] : n.cw_children)
    r = pf.prob.data.ridehailcosts[(n.n.id, child.n.id)]
    t = pf.prob.param.lambda * pf.prob.param.time_resolution * (child.n.t - n.n.t)
    total = r + t + n.dist_pickup
    
    if total < min(child.dist_pickup, child.dist_bus, child.dist_dropoff)
      child.dist_pickup = total
      child.rode_pickup = true # n.n.id == child.n.id ? n.rode_pickup : true
      child.caller_pickup = n
      tracking(child, frontier, total)
    end
  end
end

function terminal_condition(n::NodeWrapper, destination::Int64)
  return n.n.id == destination && (n.caller_pickup != nothing || 
      n.caller_bus != nothing || n.caller_dropoff != nothing)
end

function dijkstra(pf::PathFinder, origin::Node, destination::Int64)
  frontier = PriorityQueue{NodeWrapper,Float64}()
  explored = NodeWrapper[]
  
  head = pf.lookup[origin]
  head.tracking = true
  head.dist_pickup = 0
  head.dist_bus = 0
  enqueue!(frontier, head, 0)
  
  while true
    n = dequeue!(frontier)
    push!(explored, n)
    
    if terminal_condition(n, destination)
      pathroute, independentcost = unwrap(n, pf)
      path = Path(pathroute, independentcost,
          pf.prob.param.time_resolution * (n.n.t - origin.t), 0)
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
    
    #sort!(frontier, by = x->min(x.dist_pickup,x.dist_bus,x.dist_dropoff), rev=true)
  end
end

function duplicate_check(pf::PathFinder, path::Path)
  for p in pf.prob.comp.paths
    if path.route == p.route && p != path
      throw(ErrorException("This path was a repeat."))
    end
  end
end

function apply_path(pf::PathFinder, path::Path)
  o, d = od(path)
  path.index = length(pf.prob.comp.paths) + 1
  push!(pf.prob.comp.paths, path)
  push!(pf.prob.comp.ST[(o, d.id)], path.index)
  
  for arc in path.route.buses
    push!(pf.prob.comp.lookup_paths[arc], path.index)
  end
  cost = path.independentcost + pf.prob.param.lambda * path.taketime
  push!(pf.prob.comp.pathcosts, cost)
  
  duplicate_check(pf, path)
end

function undo_path(prob::Problem)
  # Update prob.comp.paths, prob.comp.pathcosts, prob.comp.ST, arcs
  path = pop!(prob.comp.paths)
  o, d = od(path)
  
  pop!(prob.comp.pathcosts)
  pop!(prob.comp.ST[(o, d.id)])
  for arc in path.route.buses
    pop!(prob.comp.lookup_paths[arc])
  end
end

function undo_path(prob::Problem, num::Int64)
  return map(undo_path, 1:num)
end

function search_path(pf::PathFinder, modify::Bool)
  count = 0 # This is only used as a statistic to display to the user.
  
  paths = Tuple{Path, Float64}[]
  for (x, (o, d)) in zip(pf.prob.sol.dualdemand, keys(pf.prob.data.demands))
    pf.prob.data.demands[(o, d)] > 0 || continue
    path, duallength = dijkstra(pf, o, d)
    excess = x - duallength
    if excess > pf.prob.param.epsilon
      count += 1
      push!(paths, (path, excess))
      sort!(paths, by = p->p[2], rev=true)
      length(paths) > prob.param.batch_path ? pop!(paths) : nothing
    end
  end
  
  if modify
    for (path, excess) in paths
      apply_path(pf, path)
    end
  end
  
  println("Paths added: ", length(paths), " out of ", count)
  return length(paths) > 0
end

function search_path(pf::PathFinder)
  return search_path(pf, true)
end
