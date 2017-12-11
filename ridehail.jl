# ridehail.jl

function reprice(prob::Problem, descent::Float64)
  m = Model(solver = GurobiSolver(Presolve=0, OutputFlag=0))
  
  @variable(m, p[1:prob.param.terminal_count^2] >= 0)
  @variable(m, s[1:prob.param.terminal_count])
  
  # Add constraints.
  for i = 1:prob.param.terminal_count
    for j = 1:prob.param.terminal_count
      if i != j
        @constraint(m, p[prob.param.terminal_count * (i - 1) + j] + s[i] - s[j] <= 1)
      end
    end
  end
  
  # Compute the demands.
  demands = zeros(prob.param.terminal_count^2)
  for (yval, path) in zip(prob.sol.y, prob.comp.paths)
    if path.route.pickup != nothing
      index = prob.param.terminal_count * (path.route.pickup[1].id - 1) +
          path.route.pickup[2].id
      demands[index] += yval
    end
    if path.route.dropoff != nothing
      index = prob.param.terminal_count * (path.route.dropoff[1].id - 1) +
          path.route.dropoff[2].id
      demands[index] += yval
    end
  end
  
  @objective(m, :Max, sum(p .* demands))
  
  solve(m)
  println(m.objVal)
  
  p = prob.param.permile_rh * getvalue(p)
  
  
  for i = 1:prob.param.terminal_count
    for j = 1:prob.param.terminal_count
      index = prob.param.terminal_count * (i - 1) + j
      prob.data.ridehailcosts[(i,j)] = descent * p[index] +
          (1 - descent) * prob.data.ridehailcosts[(i, j)]
    end
  end
  
  for (i, path) in enumerate(prob.comp.paths)
    independentcost = 0
    if path.route.pickup != nothing
      index = prob.param.terminal_count * (path.route.pickup[1].id - 1) +
          path.route.pickup[2].id
      independentcost += p[index]
    end
    if path.route.dropoff != nothing
      index = prob.param.terminal_count * (path.route.dropoff[1].id - 1) +
          path.route.dropoff[2].id
      independentcost += p[index]
    end
    path.independentcost = descent * independentcost +
        (1 - descent) * path.independentcost
    prob.comp.pathcosts[i] = (prob.param.lambda * path.taketime + path.independentcost)
  end
  
end

function reprice(prob::Problem, iters::Int64)
  for i = 1:iters
    reprice(prob, prob.param.ridepricing_descent * (1/ i)^0.6)
    autosolve(prob)
  end
end
