# This is the main script to run the SDDP for GDP Optimization problem

include("def.jl");
include("inputFunc.jl");
include("auxiliary.jl");
include("readIn.jl");
include("SDDPmain.jl");

capAddress = "/Users/haoxiangyang/Desktop/Git/GDPOptimize/PossList.csv";
capProbAdd = "/Users/haoxiangyang/Desktop/Git/GDPOptimize/ProbList.csv";
ArrAdd = "/Users/haoxiangyang/Desktop/Git/GDPOptimize/ATL_Arr_2016_01_10.csv";
DeptAdd = "/Users/haoxiangyang/Desktop/Git/GDPOptimize/ATL_Dept_2016_01_10.csv";
