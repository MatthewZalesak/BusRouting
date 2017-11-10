# solver.jl

using JuMP
using Gurobi

include("pathfinding.jl")
include("linefinding.jl")

#= Useful function for checking a current solution. =#

function feasible(prob::Problem)
  acceptable = true
  
  if minimum(round.(prob.sol.y, 5)) < 0 || minimum(round.(prob.sol.f, 5)) < 0
    warn("Negative values.")
    return false
  end
  
  for (key, value) in prob.data.demands
    if abs(sum(prob.sol.y[prob.comp.ST[key]]) - value) > 0.00001
      warn("Demand: key ", key, " value ", value, " actual ",
          sum(prob.sol.y[prob.comp.ST[key]]))
      acceptable = false
    end
  end
  
  for a in values(prob.data.arcs)
    total = sum(prob.sol.y[prob.comp.lookup_paths[a]]) - 
        prob.param.bus_capacity * sum(prob.sol.f[prob.comp.lookup_lines[a]])
    if total > 0.00001
      warn("Arc: a ", a, " constraint value ", total)
      acceptable = false
    end
  end
  return acceptable
end

#= These are modification function you can add to the 'runlp' function. =#

function mod_int(sets::Array{Tuple{Bool,Int64,Float64}})
  function f(prob::Problem, m::Model, y::Array{Variable}, f::Array{Variable})
    for (is_path, i, v) in sets
      if is_path
        @constraint(m, y[i] == v)
      else
        @constraint(m, f[i] == v)
      end
    end
  end
end

function mod_randobj(prob::Problem, m::Model, y::Array{Variable}, f::Array{Variable})
  @objective(m, :Min, sum(randn(length(y)) .* y) + sum(randn(length(f)) .* f))
end

function mod_round(prob::Problem, m::Model, y::Array{Variable}, f::Array{Variable})
  for (yp, bound) in zip(y, ceil.(prob.sol.y))
    @constraint(m, yp <= bound)
  end
  for (fl, bound) in zip(f, ceil.(prob.sol.f))
    @constraint(m, fl <= bound)
  end
  @objective(m, :Min, sum(randn(length(y)) .* y) + sum(randn(length(f)) .* f))
end

function mod_round2(prob::Problem, m::Model, y::Array{Variable}, f::Array{Variable})
  bound = sum(prob.comp.pathcosts .* ceil.(prob.sol.y)) + sum(prob.comp.linecosts .* ceil.(prob.sol.f))
  @constraint(m, sum(prob.comp.pathcosts .* y) + sum(prob.comp.linecosts .* f) <= bound)
  @objective(m, :Min, sum(randn(length(y)) .* y) + sum(randn(length(f)) .* f))
end

#= This function actually executes the optimization step. =#

function runlp(prob::Problem, modification::Array{Function})
   m = Model(solver = GurobiSolver(Presolve=0, OutputFlag=0))
  
  if prob.param.integer_y
    @variable(m, y[1:length(prob.comp.paths)] >= 0, Int)
  else
    @variable(m, y[1:length(prob.comp.paths)] >= 0)
  end
  if prob.param.integer_f
    @variable(m, f[1:length(prob.comp.lines)] >= 0, Int)
  else
    @variable(m, f[1:length(prob.comp.lines)] >= 0)
  end
  
  count = 0
  arcref = Array{Int64}(length(prob.data.arcs))
  for (i, a) in enumerate(values(prob.data.arcs))
    paths = prob.comp.lookup_paths[a]
    lines = prob.comp.lookup_lines[a]
    if true # length(paths) > 0
      @constraint(m, sum(y[paths]) - prob.param.bus_capacity * sum(f[lines]) <= 0)
      count += 1
      arcref[i] = count
    else
      arcref[i] = 0
    end
  end
  
  for (key, value) in prob.data.demands
    paths = prob.comp.ST[key]
    @constraint(m, sum(y[paths]) >= value)
  end
  
  @objective(m, :Min, sum(prob.comp.pathcosts.*y) + sum(prob.comp.linecosts.*f))
  
  for mod in modification
    mod(prob, m, y, f)
  end
  
  if ( solve(m) != :Optimal )
    throw(ErrorException("No Optimal Solution found to this LP."))
  end
  
  # Write solution.
  prob.sol.y = getvalue(y)
  prob.sol.f = getvalue(f)
  prob.sol.dualdemand = m.linconstrDuals[count + 1 : end]
  prob.sol.dualarc = Array{Float64}(length(prob.data.arcs))
  for (i, a) in enumerate(values(prob.data.arcs))
    prob.sol.dualarc[i] = arcref[i] == 0 ? 0 : -m.linconstrDuals[arcref[i]]
    a.data.dualvalue = prob.sol.dualarc[i]
  end
  prob.sol.objective = m.objVal
  return m
end

function runlp(prob::Problem, modification::Function)
  a = Function[]
  push!(a, modification)
  return runlp(prob, a)
end

function runlp(prob::Problem)
  return runlp(prob, Function[])
end

function runip(prob::Problem)
  y, f = prob.param.integer_y, prob.param.integer_f
  prob.param.integer_y, prob.param.integer_f = true, true
  runlp(prob)
  prob.param.integer_y, prob.param.integer_f = y, f
end

#= These functions run the column generation process. =#

function autosolve(prob::Problem, pf::PathFinder, lfs::Array{LineFinder})
  if prob.param.integer_f || prob.param.integer_y
    runlp(prob)
    state_solution(prob)
    return
  end
  
  i = 1000000 # max_iter
  while (i -= 1) >= 0
    @time runlp(prob)
    println("Iteration: ", i, "\t(with objective ", prob.sol.objective, ".)")
    
    if rand() > prob.param.search_weighting # Control order new vars added in.
      sp = search_path(pf)
      if sp
        continue
      end
      sl = search_line(lfs)
      if sl
        continue
      end
    else
      sl = search_line(lfs)
      if sl
        continue
      end
      sp = search_path(pf)
      if sp
        continue
      end
    end
    
    state_solution(prob)
    return
  end
  throw(ErrorException("Solver did not converge in max iterations. - MZ"))
end

function autosolve(prob::Problem)
  if prob.param.integer_f || prob.param.integer_y
    runlp(prob)
    state_solution(prob)
    return
  end
  
  # These reduce memory allocation each iteration by preallocating what is needed.
  pathfinder = PathFinder(prob)
  linefinders = [LineFinder(prob, c) for c in prob.param.cycletimes]
  autosolve(prob, pathfinder, linefinders)
  
  return pathfinder, linefinders
end
