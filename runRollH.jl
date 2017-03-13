using JuMP, Cbc, Distributions;

#capAddress = "C:\\Documents\\Git\\GDP_Optimize\\PossList.csv";
#capProbAdd = "C:\\Documents\\Git\\GDP_Optimize\\ProbList.csv";
#ArrAdd = "C:\\Documents\\Git\\GDP_Optimize\\ATL_Arr_2016_01_10.csv";
#DeptAdd = "C:\\Documents\\Git\\GDP_Optimize\\ATL_Dept_2016_01_10.csv";

capAdd = "/Users/yang902/Desktop/Codes/GDPOptimize/PossList_Toy.csv";
capProbAdd = "/Users/yang902/Desktop/Codes/GDPOptimize/ProbList_Toy.csv";
ArrAdd = "/Users/yang902/Desktop/Codes/GDPOptimize/Arr_Toy.csv";
DeptAdd = "/Users/yang902/Desktop/Codes/GDPOptimize/Dept_Toy.csv";

N = 4;
include("rollH_New.jl");

g,a,c,tc,cz,r = generateCost(ct,totalT,LC,S,TS,FSM1,FSM2,FSM3,FSM);
