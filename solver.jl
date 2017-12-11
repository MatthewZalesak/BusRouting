# solver.jl

using JuMP
using Gurobi

include("pathfinding.jl") ; println("Done loading pathfinding.")
include("linefinding.jl") ; println("Done loading linefinding.")


#= This function actually executes the optimization step. =#

function runlp(prob::Problem)
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
  
  count = length(unique(values(prob.data.arcs)))
  for (i, a) in enumerate(unique(values(prob.data.arcs)))
    paths = prob.comp.lookup_paths[a]
    lines = prob.comp.lookup_lines[a]
    @constraint(m, sum(y[paths]) - prob.param.bus_capacity * sum(f[lines]) <= 0)
  end
  
  for (key, value) in prob.data.demands
    paths = prob.comp.ST[key]
    @constraint(m, sum(y[paths]) >= value)
  end
  
  @objective(m, :Min, sum(prob.comp.pathcosts.*y) + sum(prob.comp.linecosts.*f))
  
  if ( solve(m) != :Optimal )
    throw(ErrorException("No Optimal Solution found to this LP."))
  end
  
  # Write solution.
  prob.sol.y = getvalue(y)
  prob.sol.f = getvalue(f)
  prob.sol.dualdemand = m.linconstrDuals[count + 1 : end]
  prob.sol.dualarc = -m.linconstrDuals[1:count]
  for (dual, a) in zip(prob.sol.dualarc, unique(values(prob.data.arcs)))
    a.data.dualvalue = dual
  end
  prob.sol.objective = m.objVal
  return m
end


#= These functions run the column generation process. =#

function autosolve(prob::Problem, pf::PathFinder, lf::LineFinder)
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
      sl = search_line(lf)
      if sl
        continue
      end
    else
      sl = search_line(lf)
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
  linefinder = LineFinder(prob, maximum(prob.param.cycletimes))
  autosolve(prob, pathfinder, linefinder)
  
  return # pathfinder, linefinder
end

function autoint(prob::Problem)
  save_f, save_y = prob.param.integer_f, prob.param.integer_y
  prob.param.integer_f, prob.param.integer_y = true, true
  autosolve(prob)
  prob.param.integer_f, prob.param.integer_y = save_f, save_y
end
