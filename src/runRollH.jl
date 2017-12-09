using JuMP, Cbc, Distributions, CPLEX;

#capAddress = "C:\\Documents\\Git\\GDP_Optimize\\PossList.csv";
#capProbAdd = "C:\\Documents\\Git\\GDP_Optimize\\ProbList.csv";
#ArrAdd = "C:\\Documents\\Git\\GDP_Optimize\\ATL_Arr_2016_01_10.csv";
#DeptAdd = "C:\\Documents\\Git\\GDP_Optimize\\ATL_Dept_2016_01_10.csv";

capAdd = "/Users/yang902/Desktop/Codes/GDPOptimize/PossList_Toy.csv";
capProbAdd = "/Users/yang902/Desktop/Codes/GDPOptimize/ProbList_Toy.csv";
ArrAdd = "/Users/yang902/Desktop/Codes/GDPOptimize/Arr_Toy.csv";
DeptAdd = "/Users/yang902/Desktop/Codes/GDPOptimize/Dept_Toy.csv";

N = 1;
totalT = 5;
currentT = 1;
include("def.jl");
include("rollH_New.jl");

FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,capDict,probDict = initiMain(capAdd,capProbAdd,ArrAdd,DeptAdd,totalT,N);
