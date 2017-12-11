# pathfinding.jl

# Try statement protects items that cannot be initialized more than once.
try
  pathfinding_init
catch
  
  type NodeWrapper
    n::Node
    arc_children::Array{NodeWrapper}
    tracking::Bool                            # Has this variable been touched?
    dist_pickup::Float64
    dist_bus::Float64
    dist_dropoff::Float64
    caller_pickup::Union{Void,NodeWrapper}
    caller_bus::Union{Void,NodeWrapper}
    caller_dropoff::Union{Void,NodeWrapper}
    
    function NodeWrapper(n::Node)
      return new(n, NodeWrapper[], false, Inf, Inf,
          Inf, nothing, nothing, nothing)
    end
  end
  
  using DataStructures # Load just once for convenicen
end
pathfinding_init = true


function cleanup(a::Array{NodeWrapper})
  for x in a
    x.tracking = false
    x.dist_pickup, x.dist_bus, x.dist_dropoff = Inf, Inf, Inf
    x.caller_pickup, x.caller_bus, x.caller_dropoff = nothing, nothing, nothing
  end
end

function cleanup(a::PriorityQueue{NodeWrapper,Float64})
  for x = keys(a)
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
      for child in prob.data.arc_children[nw.n] # Probably a complete graph...
        push!(nw.arc_children, lookup[child])
      end
    end
    
    return new(prob, graph, lookup)
  end
end



function unwrap(n::NodeWrapper, pf::PathFinder)
  pickup = nothing::Union{Void,Tuple{Node,Node}}
  buses = Arc[]
  dropoff = nothing::Union{Void,Tuple{Node,Node}}
  independentcost = 0
  taketime = 0
  
  while true
    if n.dist_dropoff < n.dist_pickup && n.dist_dropoff < n.dist_bus
      parent = n.caller_dropoff
      dropoff = (parent.n, n.n)
      independentcost += pf.prob.data.ridehailcosts[(parent.n.id, n.n.id)]
      taketime += pf.prob.data.distances[(parent.n.id, n.n.id)] / pf.prob.param.speed
      n = parent
    elseif n.dist_bus < n.dist_pickup
      parent = n.caller_bus
      push!(buses, pf.prob.data.arcs[(parent.n, n.n)])
      taketime += pf.prob.data.arcs[(parent.n, n.n)].data.time
      n = parent
    else
      parent = n.caller_pickup
      pickup = (parent.n, n.n)
      independentcost += pf.prob.data.ridehailcosts[(parent.n.id, n.n.id)]
      taketime += pf.prob.data.distances[(parent.n.id, n.n.id)] / pf.prob.param.speed
      n = parent
      break
    end
    if n.caller_pickup == nothing && n.caller_bus == nothing && 
        n.caller_dropoff == nothing
      break
    end
  end
  pathroute = PathRoute(pickup, reverse(buses), dropoff) 
  return pathroute, independentcost, taketime
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

function update_nodewrapper_dropoff(n::NodeWrapper, destination::NodeWrapper,
    frontier::PriorityQueue{NodeWrapper,Float64}, pf::PathFinder)
  dropoff = destination.n
  
  if dropoff != n.n
    distance = n.dist_bus
    r = pf.prob.data.ridehailcosts[(n.n.id, dropoff.id)]
    t = pf.prob.param.lambda * pf.prob.data.distances[(n.n.id, dropoff.id)] /
        pf.prob.param.speed
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
    t = pf.prob.param.lambda * pf.prob.data.arcs[(n.n, child.n)].data.time
    z = pf.prob.data.arcs[(n.n, child.n)].data.dualvalue
    total = t + z + distance
    
    if total < min(child.dist_pickup, child.dist_bus, child.dist_dropoff)
      child.dist_bus = total
      child.caller_bus = n
      tracking(child, frontier, total)
    end
  end
end

# This only runs once for the origin node.  Changed to reflect this.
function update_nodewrapper_pickup(n::NodeWrapper,
    frontier::PriorityQueue{NodeWrapper,Float64},  pf::PathFinder)
  for child in [x for x in pf.graph if x != n]
    r = pf.prob.data.ridehailcosts[(n.n.id, child.n.id)]
    t = pf.prob.param.lambda * pf.prob.data.distances[(n.n.id, child.n.id)] / pf.prob.param.speed
    total = r + t + n.dist_pickup
    
    if total < min(child.dist_pickup, child.dist_bus, child.dist_dropoff)
      child.dist_pickup = total
      child.caller_pickup = n
      tracking(child, frontier, total)
    end
  end
end


function dijkstra(pf::PathFinder, origin::Node, destination::Node)
  # println("Fresh")
  frontier = PriorityQueue{NodeWrapper,Float64}()
  explored = NodeWrapper[]
  
  head = pf.lookup[origin]
  head.tracking = true
  head.dist_pickup = 0
  head.dist_bus = 0
  # println("DIJK: ", head, " with distance  ", min(head.dist_pickup, head.dist_bus, head.dist_dropoff))
  
  update_nodewrapper_pickup(head, frontier, pf)
  update_nodewrapper_bus(head, frontier, pf)
  push!(explored, head)
  
  while true
    n = dequeue!(frontier)
    push!(explored, n)
    # println("DIJK: ", n, " with distance  ", min(n.dist_pickup, n.dist_bus, n.dist_dropoff))
    
    if n.n == destination
      if n.caller_pickup == nothing && n.caller_bus == nothing &&
          n.caller_dropoff == nothing
        throw(ErrorException("Dijkstra failed.  Logic error."))
      end
      pathroute, independentcost, taketime = unwrap(n, pf)
      path = Path(pathroute, independentcost, taketime, 0)
      dualdistance = min(n.dist_pickup, n.dist_bus, n.dist_dropoff)
      cleanup(frontier)
      cleanup(explored)
      return path, dualdistance
    end
    
    update_nodewrapper_bus(n, frontier, pf)
    update_nodewrapper_dropoff(n, pf.lookup[destination], frontier, pf)
  end
end

function duplicate_check(pf::PathFinder, path::Path)
  for (i, p) in enumerate(pf.prob.comp.paths)
    if path.route == p.route && p != path
      throw(ErrorException("This path was a repeat. (" * string(i) * ")"))
    end
  end
end

function apply_path(pf::PathFinder, path::Path, o, d)
  # o, d = od(path)
  path.index = length(pf.prob.comp.paths) + 1
  push!(pf.prob.comp.paths, path)
  push!(pf.prob.comp.ST[(o, d)], path.index)
  
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
  pop!(prob.comp.ST[(o, d)])
  for arc in path.route.buses
    pop!(prob.comp.lookup_paths[arc])
  end
end

function undo_path(prob::Problem, num::Int64)
  return map(undo_path, 1:num)
end

function search_path(pf::PathFinder, modify::Bool)
  count = 0 # This is only used as a statistic to display to the user.
  
  paths = Tuple{Path, Float64, Node, Node, Float64, Float64}[]
  for (x, (o, d)) in zip(pf.prob.sol.dualdemand, keys(pf.prob.data.demands))
    pf.prob.data.demands[(o, d)] > 0 || continue
    path, duallength = dijkstra(pf, o, d)
    excess = x - duallength
    if excess > pf.prob.param.epsilon
      count += 1
      push!(paths, (path, excess, o, d, duallength, x))
      sort!(paths, by = p->p[2], rev=true)
      length(paths) > prob.param.batch_path ? pop!(paths) : nothing
    end
  end
  
  if modify
    for (path, excess, o, d, dua, x) in paths
      #println("Adding a path.", " excess ", excess)
      #println("Length", length(pf.prob.comp.paths), " excess ", excess, " dual ", dua)
      #println("Origin: ", o, " Destination: ", d, " Against: ", x)
      apply_path(pf, path, o, d)
    end
  end
  
  println("Paths added: ", length(paths), " out of ", count)
  return length(paths) > 0
end

function search_path(pf::PathFinder)
  return search_path(pf, true)
end
