# l2.jl

try
  linefinding_init
catch
  type ColorNodeWrapper
    n::Node
    children::Array{ColorNodeWrapper}
    colors::Array{Dict{Array{Int64},Tuple{Float64,ColorNodeWrapper,Int64}}}
    iteration::Int64
    
    function ColorNodeWrapper(n::Node)
      return new(n, ColorNodeWrapper[], Dict{Array{Int64},Tuple{Float64,ColorNodeWrapper,Int64}}[], 0)
    end
  end
end
linefinding_init = true

type ColorArc
  color::Int64
  o::ColorNodeWrapper
  d::ColorNodeWrapper
  arc1::Arc
  arc2::Arc
end


type LineFinder
  color_arcs::Dict{Tuple{ColorNodeWrapper,ColorNodeWrapper},ColorArc}
  graph::Array{ColorNodeWrapper}
  limit::Int64
  lookup::Dict{Node,ColorNodeWrapper}
  prob::Problem
  
  function LineFinder(prob::Problem, limit::Int64)
    color_arcs = Dict{Tuple{ColorNodeWrapper,ColorNodeWrapper},ColorArc}()
    graph = Array{ColorNodeWrapper}(length(prob.data.terminals))
    lookup = Dict{Node,ColorNodeWrapper}()
    
    for (i, n) in enumerate(prob.data.terminals)
      cnw = ColorNodeWrapper(n)
      graph[i], lookup[n] = cnw, cnw
    end
    for cnw in graph
      for child in prob.data.arc_children[cnw.n]
        push!(cnw.children, lookup[child])
      end
    end
    
    for ((o, d), a) in prob.data.arcs
      if o.id <= d.id
        o_node, d_node = lookup[o], lookup[d]
        a2 = prob.data.arcs[(d, o)]
        carc = ColorArc(0, o_node, d_node, a, a2)
        color_arcs[(o_node, d_node)] = carc
        color_arcs[(d_node, o_node)] = carc
      end
    end
    
    return new(color_arcs, graph, limit, lookup, prob)
  end
end


function cleanup(lf::LineFinder)
  for cnw in lf.graph
    cnw.colors = [Dict{Array{Int64},Tuple{Float64,ColorNodeWrapper,Int64}}()
        for i in 1:lf.limit]
    cnw.iteration = 0
  end
end


function random_color(lf::LineFinder)
  for ca in values(lf.color_arcs)
    ca.color = rand(1:lf.limit)
  end
end


function process_node(node::ColorNodeWrapper, iteration::Int64, lf::LineFinder)
  i = iteration
  if node.iteration == iteration - 1
    for cnw in node.children                   # For each location we can go to
      color = lf.color_arcs[(node, cnw)].color
      
      feasible_choices = iteration > 1 ?    # Each color combo we can come from
          [(x, stuff) for (x, stuff) in node.colors[i - 1] if !(color in x)] : 
          [(Int64[], (0, cnw, -1))]
      for (colorful, (distance, caller, last_color)) in feasible_choices
        new_combo = sort!(vcat(colorful, color))
        a1 = lf.prob.data.arcs[(node.n, cnw.n)]
        a2 = lf.prob.data.arcs[(cnw.n, node.n)]
        dual_distance = lf.prob.param.bus_capacity *
            (a1.data.dualvalue + a2.data.dualvalue)
        milage_cost = 2 * a1.data.distance * lf.prob.param.permile_bus
        distance += (dual_distance - milage_cost)
        
        if !( new_combo in keys(cnw.colors[i]) ) ||
            distance > cnw.colors[i][new_combo][1]
          cnw.colors[i][new_combo] = (distance, node, color)
          cnw.iteration = i
        end
      end
    end
  end
end


function line_backtrack(node::ColorNodeWrapper, colors::Array{Int64})
  if length(colors) == 0
    return [node]
  else
    distance, caller, last_color = node.colors[length(colors)][colors]
    parent_colors = deleteat!(copy(colors), findfirst(colors, last_color))
    return push!(line_backtrack(caller, parent_colors), node)
  end
end


function find_line(lf::LineFinder)
  best_colors = Int64[]
  best_dist = -Inf
  best_start = nothing::Union{ColorNodeWrapper,Void}
  
  for cnw in lf.graph
    for dict in cnw.colors
      for (colors, (distance, caller, last_color)) in dict
        if distance > best_dist
          best_colors = colors
          best_dist = distance
          best_start = cnw
        end
      end
    end
  end
  
  line_nodes = line_backtrack(best_start, best_colors)
  line_arcs = Arc[]
  line_length = 0
  for (o, d) in zip(line_nodes[1:end - 1], line_nodes[2:end])
    a1 = lf.prob.data.arcs[(o.n, d.n)]
    a2 = lf.prob.data.arcs[(d.n, o.n)]
    push!(line_arcs, a1) ; line_length += a1.data.distance
    push!(line_arcs, a2) ; line_length += a2.data.distance
  end
  
  cost = lf.prob.param.bus_fixedcost + lf.prob.param.permile_bus * line_length
  line = Line(line_arcs, cost, 0)
  return line, best_dist
end


function longest_path_dp(lf::LineFinder)
  cleanup(lf)
  random_color(lf)
  
  for i = 1:lf.limit
    for cnw in lf.graph
      process_node(cnw, i, lf)
    end
  end
  
  line, dual_value = find_line(lf)
end


function apply_line(line::Line, lf::LineFinder)
  line.index = length(lf.prob.comp.lines) + 1
  
  push!(lf.prob.comp.lines, line)
  push!(lf.prob.comp.linecosts, line.cost)
  for arc in line.line
    push!(lf.prob.comp.lookup_lines[arc], line.index)
  end
  
  for l in lf.prob.comp.lines
    if l.line == line.line && l != line
      throw(ErrorException("This line was a repeat."))
    end
  end
end


function undo_line(prob::Problem)
  line = pop!(prob.comp.lines)
  pop!(prob.comp.linecosts)
  for arc in line.line
    pop!(prob.comp.lookup_lines[arc])
  end
  line
end


function search_line(lf::LineFinder)
  line, dual_value = longest_path_dp(lf)
  if dual_value > lf.prob.param.bus_fixedcost + lf.prob.param.epsilon
    apply_line(line, lf)
    # println("Line length: ", length(line.line), " Excess: ", dual_value - bus_fixedcost)
    return true
  else
    return false
  end
end
