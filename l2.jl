# linefinding.jl

# Try statement protects items that cannot be initialized more than once.  Since
# MultiNodeWrapper references itself it will cause an error if we try to reload it.
try
  linefinding_init
catch
  type MultiNodeWrapper
    n::Node
    distance::Float64
    caller::Union{Void, MultiNodeWrapper}   # 'caller' field enables backtracking.
    children::Array{MultiNodeWrapper}
    
    function MultiNodeWrapper(n::Node)
      return new(n, -Inf, nothing, MultiNodeWrapper[])
    end
  end
end
linefinding_init = true

type MultiArc
  o::MultiNodeWrapper
  d::MultiNodeWrapper
  dualvalue::Float64
  arcs::Array{Arc}
end

#= LineFinder holds a compression of a graph to find cyclic bus lines. =#
type LineFinder
  cycletime::Int64
  multi_arcs::Dict{Tuple{MultiNodeWrapper,MultiNodeWrapper},MultiArc}
  graph::Array{MultiNodeWrapper}
  lookup::Dict{Node,MultiNodeWrapper}
  prob::Problem
  
  function LineFinder(prob::Problem, cycletime::Int64)
    maximum_time = prob.data.terminals[end].t
    @assert(cycletime + 1 <= maximum_time)
    
    # Define primary components for type.
    multi_arcs = Dict{Tuple{MultiNodeWrapper,MultiNodeWrapper},MultiArc}()
    graph = Array{MultiNodeWrapper}(prob.param.terminal_count * (cycletime + 1))
    lookup = Dict{Node,MultiNodeWrapper}()
    
    # Construct the object.
    
    for i = 1:length(graph) # Populate graph, two loops
      n = prob.data.terminals[i]
      mnw = MultiNodeWrapper(n)
      graph[i], lookup[n] = mnw, mnw
    end
    for mnw in graph
      for child in prob.data.arc_children[mnw.n]
        child.t <= cycletime + 1 && push!(mnw.children, lookup[child])
      end
    end
    
    for ((o, d), a) in prob.data.arcs # Populate multi_arcs
      if d.t <= cycletime + 1
        o_wrapper, d_wrapper = lookup[o], lookup[d]
        multi_arcs[(o_wrapper, d_wrapper)] = MultiArc(o_wrapper, d_wrapper,0, Arc[])
      end
    end
    for ((o, d), a) in prob.data.arcs # (collapsing arcs onto cyclic time window)
      ot = (o.t - 1) % cycletime + 1
      dt = (d.t - 1) % cycletime > 0 ? (d.t - 1) % cycletime + 1 : cycletime + 1
      (ot < dt && dt - ot == d.t - o.t) || continue
      o_short = graph[(ot - 1) * prob.param.terminal_count + o.id] # Uses that nodes
      d_short = graph[(dt - 1) * prob.param.terminal_count + d.id] # are sorted.
      push!(multi_arcs[(o_short, d_short)].arcs, a)
    end
    
    return new(cycletime, multi_arcs, graph, lookup, prob)
  end
end

function update(lfs::Array{LineFinder})
  for lf in lfs
    for ma in values(lf.multi_arcs)
      ma.dualvalue = 0
      for a in ma.arcs
        ma.dualvalue += a.data.dualvalue
      end
    end
  end
end

function cleanup(lf::LineFinder)
  for mnw in lf.graph
    mnw.caller = nothing
    mnw.distance = -Inf
  end
end

function bellmanford(lf::LineFinder, origin::Int64)
  lf.graph[origin].distance = 0
  for mnw in lf.graph
    for child in mnw.children
      distance = mnw.distance + 
          lf.prob.param.bus_capacity * lf.multi_arcs[(mnw, child)].dualvalue -
          ( lf.prob.param.permile_bus * 
              lf.prob.data.distances[(mnw.n.id, child.n.id)] *
              length(lf.multi_arcs[(mnw, child)].arcs) )
      if distance > child.distance
        child.distance = distance
        child.caller = mnw
      end
    end
  end
  
  tail = lf.graph[length(lf.graph) - lf.prob.param.terminal_count + origin]
  len = tail.distance
  @assert(tail.n.id == origin)  # Hopefully unecessary, error checking only.
  
  line = MultiArc[]
  while tail.caller != nothing
    parent = tail.caller
    push!(line, lf.multi_arcs[(parent, tail)])
    tail = parent
  end
  reverse!(line)
  
  cleanup(lf)
  return line, len
end

function expand_line(lf::LineFinder, ma::Array{MultiArc})
  line = Arc[]
  iteration = 1
  cont = true
  while cont
    for a in ma
      iteration <= length(a.arcs) || (cont = false ; break)
      push!(line, a.arcs[iteration])
    end
    iteration += 1
  end
  
  cost = 0
  cost += lf.prob.param.bus_fixedcost
  for a in line
    cost += lf.prob.param.permile_bus * lf.prob.data.distances[(a.o.id, a.d.id)]
  end
  
  return Line(line, cost, lf.cycletime, 0)
end

function dualvalue(lf::LineFinder, line::Line)
  value = 0
  for a in line.line
    value += ( lf.prob.param.bus_capacity * a.data.dualvalue -
        lf.prob.param.permile_bus * lf.prob.data.distances[(a.o.id, a.d.id)] )
  end
  return value
end

function duplicate_check(lf::LineFinder, line::Line, len::Float64)
  for l in lf.prob.comp.lines
    if l.line == line.line && l != line
      l.index > length(lf.prob.sol.f) && return true
      throw(ErrorException("This line was a repeat." * string(len)))
    end
  end
  return false
end

function apply_line(lf::LineFinder, line::Line, len::Float64)
  line.index = length(lf.prob.comp.lines) + 1
  duplicate_check(lf, line, len) && return # Skip duplicates added this session.
  push!(lf.prob.comp.lines, line)
  
  for arc in line.line
    push!(lf.prob.comp.lookup_lines[arc], line.index)
  end
  push!(lf.prob.comp.linecosts, line.cost)
end

function undo_line(prob::Problem)
  # Upate prob.comp.linecosts, prob.comp.lookup_lines[arc], prob.comp.lines
  line = pop!(prob.comp.lines)
  pop!(prob.comp.linecosts)
  for arc in line.line
    pop!(prob.comp.lookup_lines[arc])
  end
  return line
end

function undo_line(prob::Problem, num::Int64)
  return map(undo_line, 1:num)
end

function search_line(lfs::Array{LineFinder}, modify::Bool)
  update(lfs)
  
  lines = Tuple{LineFinder,Array{MultiArc},Float64}[]
  for lf in lfs
    for origin in 1:lf.prob.param.terminal_count
      arcs, len = bellmanford(lf, origin)
      if len > lf.prob.param.bus_fixedcost + lf.prob.param.epsilon
        push!(lines, (lf, arcs, len))
        sort!(lines, by = x->x[3], rev=true)
        length(lines) > lf.prob.param.batch_line ? pop!(lines) : nothing
      end
    end
  end
  
  if modify
    for (lf, multiarcs, len) in lines
      line = expand_line(lf, multiarcs)
      apply_line(lf, line, len)
    end
  end
  
  println("Lines added: ", length(lines))
  return length(lines) > 0
end

function search_line(lfs::Array{LineFinder})
  return search_line(lfs, true)
end
