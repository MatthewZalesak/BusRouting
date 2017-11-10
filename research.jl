# research.jl

#= A file with routines that get useful exploratory information. =#

function measure_rounding_performance(prob::Problem, num_iter::Int64)
  counter = 0
  n = 0
  
  runlp(prob)
  lp_y = copy(prob.sol.y)
  lp_f = copy(prob.sol.f)

  for i = 1:num_iter
    println("Iteration: ", i, "\t\t\t\t", counter / n)
    n += 1
    prob.sol.y = copy(lp_y)
    prob.sol.f = copy(lp_f)
    runlp(prob, mod_round)
    found = false
    for y in prob.sol.y
      if y % 1.0 != 0
        counter += 1
        found = true
        break
      end
    end
    if found
      continue
    end
    for f in prob.sol.f
      if f % 1.0 != 0
        counter += 1
        break
      end
    end
  end
  println("Complete: \t\t\t\t", counter / n)
  return counter
end

#= List values of y entries corresponding to each ST pair that are fractional. =#
function number_carsharable_y(prob::Problem)
  println("A '*' after an entry means it only uses a ride hail.")
  for (key, value) in prob.data.demands
    if value > 0
      paths = prob.comp.ST[key]
      fractional = false
      for index in paths
        if round(prob.sol.y[index], 7) % 1.0 != 0
          fractional = true
          break
        end
      end
      if fractional
        println("Blob Found: ", key[1], " ", key[2], " : d ", value)
        for index in paths
          if prob.sol.y[index] == 0
            continue
          end
          star = ( length(prob.comp.paths[index].route.buses) > 0 
              || prob.comp.paths[index].route.dropoff != nothing ) ? "" : "*"
          println("\t\t", prob.sol.y[index], star)
        end
      end
    end
  end
end

function balanced_eq(prob::Problem, all::Bool)
  println("Lines with '*' have more fractional path variables than line varaibles.")
  starred = 0
  for a in values(prob.data.arcs)
    yc = 0
    for index in prob.comp.lookup_paths[a]
      if prob.sol.y[index] % 1.0 != 0
        yc += 1
      end
    end
    
    fc = 0
    for index in prob.comp.lookup_lines[a]
      if prob.sol.f[index] % 1.0 != 0
        fc += 1
      end
    end
    
    if yc > 0 || fc > 0
      star = yc > fc
      if !all && !star
        continue
      end
      star_string = star ? "*" : " "
      if star
        starred += 1
      end
      println(star_string, " y: ", yc, " f: ", fc, " from Arc ", a)
      if !all
        for index in prob.comp.lookup_paths[a]
          println("   ID ", index, " + ", prob.sol.y[index])
        end
      end
    end
  end
  println("Total '*' lines : ", starred)
end

function balanced_eq(prob::Problem)
  return balanced_eq(prob, true)
end

function research_instant_rounding(prob::Problem)
  for i = 1:length(prob.sol.y)
    if prob.sol.y[i] % 1.0 != 0
      prob.sol.y[i] = rand() > 0.5 ? floor(prob.sol.y[i]) : ceil(prob.sol.y[i])
    end
  end
  for j = 1:length(prob.sol.f)
    if true # prob.sol.f[j] % 1.0 != 0
      prob.sol.f[j] = rand() > 0.5 ? floor(prob.sol.f[j]) : ceil(prob.sol.f[j])
    end
  end
end

function credited_rounding(prob::Problem, ys::Array{Float64}, fs::Array{Float64}, 
    up::Array{Tuple{Bool,Int64,Bool}})
  #up (is this a car?, index, is this rounding up? (else down))
  
  function internal(prob::Problem, m::Model, y::Array{Variable}, f::Array{Variable})
    for (is_car, index, upping) in up
      if is_car
        @constraint(m, y[index] == ceil(ys[index]))
      else
        @constraint(m, f[index] == ceil(fs[index]))
      end
    end
    for (yp, bound) in zip(y, ceil.(ys))
      @constraint(m, yp <= bound)
    end
    for (fl, bound) in zip(f, ceil.(fs))
      @constraint(m, fl <= bound)
    end
  end
  
  runlp(prob, internal)
end

function has_fractional(ys::Array{Float64}, fs::Array{Float64})
  if maximum([round(y, 8) % 1.0 != 0.0 for y in ys])
    return true
  elseif length(fs) == 0
    return false
  else
    return maximum([round(f, 8) % 1.0 != 0.0 for f in fs])
  end
end

function has_fractional(prob::Problem)
  return has_fractional(prob.sol.y, prob.sol.f)
end

function has_fractional(sol::Solution)
  return has_fractional(sol.y, sol.f)
end

function fractional_usage(prob::Problem)
  for a in values(prob.data.arcs)
    total = sum(prob.sol.y[prob.comp.lookup_paths[a]])
    if total % 1.0 != 0
      println("Non Fractional Total: ", total, " ", a.o, " ", a.d)
      println("\ty: ", prob.comp.lookup_paths[a])
      println("\tf: ", prob.comp.lookup_lines[a])
    end
  end
end

function fractional_st(prob::Problem)
  for (key, value) in prob.data.demands
    paths = prob.comp.ST[key]
    if length(paths) > 0
      total = sum(prob.sol.y[paths])
      if total > 0 && maximum([prob.sol.y[i] % 1.0 != 0 for i in paths])
        println("Pair: ", key[1], " ", key[2], " total ", total)
        for p in paths
          println("\t", "ID ", p, "\t", prob.sol.y[p])
        end
      end
    end
  end
end

#function random_test()
#  
#end

#function find_breaker(max_iter::Int64)
#  seeds = map(UInt32, rand(1:2^32 - 1, 4, max_iter))
#  
#  for i = 1:max_iter
#    
#  end
#end
