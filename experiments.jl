# experiments.jl

exp0 = quote
  srand(UInt32[0x6bef474d, 0x991214d6, 0x1b5f02c4, 0x13f45fe6])
  demand_count = 10000
  terminal_count = 6
  time_resolution = 5.0
  timelength = 120
  permile_rh = 2
  sep_ratio = 2
  speed = 0.5
  height = 2.0
  width = 2.0
  req_type = :TwoCities
  batch_path = 5
  batch_line = 5
  bus_capacity = 20
  bus_fixedcost = 200.0
  cycletimes = [6]
  epsilon = 0.000001
  integer_f = false
  integer_y = false
  lambda = 1.0
  search_weighting = 0.7
  permile_bus = 1.0
end

exp1 = quote
  srand(UInt32[0x18806502, 0xdf92f559, 0x537b84bd, 0xf575a265])
  demand_count = 10000
  terminal_count = 6
  time_resolution = 5.0
  timelength = 120
  permile_rh = 2
  sep_ratio = 2
  speed = 0.5
  height = 2.0
  width = 2.0
  req_type = :TwoCities
  batch_path = 5
  batch_line = 5
  bus_capacity = 20
  bus_fixedcost = 200.0
  cycletimes = [6]
  epsilon = 0.000001
  integer_f = false
  integer_y = false
  lambda = 1.0
  search_weighting = 0.7
  permile_bus = 1.0
end

exp3 = quote
  srand(UInt32[0xa09fb98e, 0x4df555df, 0xb2b59a3f, 0xb0aed81c])
  demand_count = 10000
  terminal_count = 10
  time_resolution = 5.0
  timelength = 120
  permile_rh = 2
  speed = 0.5
  height = 10.0
  width = 10.0
  req_type = :Basic
  batch_path = 5
  batch_line = 5
  bus_capacity = 20
  bus_fixedcost = 200.0
  cycletimes = [6,12]
  epsilon = 0.0001
  integer_f = false
  integer_y = false
  lambda = 1.0
  search_weighting = 0.7
  permile_bus = 1.0
  # Produces 58 fractional y variables, 58 fractional f variables. (1/3 regime)
  # Objective value 155963.87 after 1432 iterations (i=98568).
  # Number of paths: 4568  (2183 selected)
  # Number of lines: 4159  (833 selected)
  # 928.380974 seconds (791.27 M allocations: 38.366 GiB, 0.90% gc time)
  #
  # Integer (y) solution:
  # Objective value 155967.90797412218!
  # Number of paths: 4568  (2169 selected)
  # Number of lines: 4159  (836 selected)
end

exp4 = quote
  eval(exp3)
  bus_fixedcost = 50.0
  # Produces no fractional variables.
  # Objective value 144189.00956727553 after 1274 iterations (i=98726).
  # Number of paths: 4296  (2039 selected)
  # Number of lines: 3726  (890 selected)
  # 769.913141 seconds (691.42 M allocations: 32.912 GiB, 0.92% gc time)
end

exp5 = quote
  eval(exp3)
  bus_fixedcost = 5.0
  # Produces no fractional variables.
  # Objective value 140291.97145408177 after 1261 iterations (i=98739).
  # Number of paths: 4295  (2043 selected)
  # Number of lines: 3679  (903 selected)
  # 805.033862 seconds (690.32 M allocations: 32.758 GiB, 0.89% gc time)
  #
  # Also solved by:
  # Used "always full arcs LP" switch.
  # 1248 iterations (i=98752).
  # Number of paths: 4285  (2041 selected)
  # Number of lines: 3655  (904 selected)
  # 534.697248 seconds (714.42 M allocations: 35.816 GiB, 1.65% gc time)
  #
  # Also solved by (same as above...):
  # Number of paths: 4292  (2042 selected)
  # Number of lines: 3636  (905 selected)
  # 424.011453 seconds (716.70 M allocations: 35.899 GiB, 1.59% gc time)
end

exp6 = quote
  eval(exp3)
  bus_fixedcost = 125.0
  # Produces no fractional variables.
  # Objective value 150234.45124689917 after 1364 iterations (i=98636).
  # Number of paths: 4414  (2108 selected)
  # Number of lines: 4076  (852 selected)
  # 502.956642 seconds (773.64 M allocations: 39.471 GiB, 1.53% gc time)
end

exp7 = quote
  eval(exp3)
  bus_fixedcost = 165.0
  # Produces 6 fractional y and f variables.
  # Objective value 153328.03915379813 after 1358 iterations (i=90642).
  # Number of paths: 4446  (2127 selected)
  # Number of lines: 3981  (846 selected)
  # 508.640989 seconds (782.18 M allocations: 39.649 GiB, 1.46% gc time)
end

exp8 = quote
  eval(exp3)
  bus_capacity = 1
  bus_fixedcost /= 20
  permile_bus /= 20
  # Produces 56 fractional paths and 670 fractional lines.
  # Objective value 155963.87828583454 in 1393 iterations (i=98607).
  # Number of paths: 4549  (2183 selected)
  # Number of lines: 4083  (828 selected)
  # 1056.626259 seconds (814.02 M allocations: 41.386 GiB, 0.90% gc time)
  #
  # Integer solution:
  # The problem is solved with objective 155978.93175262408! (1.00009651893)
  # Number of paths: 4549  (2189 selected)
  # Number of lines: 4083  (764 selected)
  #
  # Linear solve + rounding procedure.
  # Objective value 157911.9065528978 (ratio 1.0124899556678246)
  # Number of paths: 4549  (2170 selected)
  # Number of lines: 4083  (737 selected)
end

exp9 = quote
  eval(exp4)
  bus_capacity = 1
  bus_fixedcost /= 20
  permile_bus /= 20
  # There were 0 fractional paths and 843 fractional lines.
  # Objective value 144189.0095672757 in 1299 iterations (i=98701).
  # Number of paths: 4289  (2040 selected)
  # Number of lines: 3865  (892 selected)
  # 917.355124 seconds (724.53 M allocations: 36.620 GiB, 0.97% gc time)
  #
  # Integer solution:
  # Objective 144203.2652024319!  (1.000098867695943)
  # Number of paths: 4289  (2052 selected)
  # Number of lines: 3865  (826 selected)
  #
  # Linear + rounding procedure.
  # Objective value 144936.32040198802 (ratio 1.0051828557318971)
  # Number of paths: 4289  (2032 selected)
  # Number of lines: 3865  (804 selected)
end

exp10 = quote
  eval(exp5)
  bus_capacity = 1
  bus_fixedcost /= 20
  permile_bus /= 20
end

exp11 = quote
  eval(exp6)
  bus_capacity = 1
  bus_fixedcost /= 20
  permile_bus /= 20
end

exp12 = quote
  eval(exp7)
  bus_capacity = 1
  bus_fixedcost /= 20
  permile_bus /= 20
  # Produces 0 fractional paths and 767 fractional lines.
  # Objective value 153328.03915379877 in 1371 (i=98629)
  # Number of paths: 4450  (2122 selected)
  # Number of lines: 4057  (848 selected)
  # 1039.949327 seconds (784.26 M allocations: 39.918 GiB, 0.89% gc time)
  #
  # Integer solution:
  # Objective value 153335.95900183098! (1.000051652966254)
  # Number of paths: 4450  (2143 selected)
  # Number of lines: 4057  (760 selected)
  #
  # Linear + rouning procedure.
  # Objective value 155099.82883021983 (ratio 1.011555549045037)
  # Number of paths: 4450  (2114 selected)
  # Number of lines: 4057  (746 selected)
end

exp13 = quote
  srand(UInt32[0xa385c8aa, 0x05183f54, 0x86916f4c, 0xefdcf863])
  demand_count = 10000
  terminal_count = 8
  time_resolution = 5.0
  timelength = 120
  permile_rh = 2
  speed = 0.5
  height = 2.0
  width = 2.0
  req_type = :TwoCity
  batch_path = 5
  batch_line = 5
  bus_capacity = 1 # (20 / 20)
  bus_fixedcost = 200.0 / 20
  cycletimes = [6]
  epsilon = 0.000001
  integer_f = false
  integer_y = false
  lambda = 1.0
  search_weighting = 0.7
  permile_bus = 1.0 / 20
end

exp14 = quote
  srand(UInt32[0xa385c8aa, 0x05183f54, 0x86916f4c, 0xefdcf863])
  demand_count = 10000
  terminal_count = 8
  time_resolution = 5.0
  timelength = 120
  permile_rh = 2
  speed = 0.5
  height = 2.0
  width = 2.0
  req_type = :Basic
  batch_path = 5
  batch_line = 5
  bus_capacity = 1 # (20 / 20)
  bus_fixedcost = 200.0 / 20
  cycletimes = [6]
  epsilon = 0.000001
  integer_f = false
  integer_y = false
  lambda = 1.0
  search_weighting = 0.7
  permile_bus = 1.0 / 20
end

exp15 = quote
  eval(exp14)
  bus_fixedcost = 100.0 / 20
end

name = :exp9
experiment = eval(name)
