function createStream(T,N,M,S,LC,TS,FSet1,FSet2,FSet3,FSet,F3,g,c,a,tc)
    # create M forward iteration problems and return the array containing the models
    mfList = [];
    TSet = 1:T;
    for im in 1:M
        m = Model();
        # set up the variables:
        @variable(m,X[FSet1,0:T],Bin);  # the indicator of clearance
        @variable(m,D[FSet1,0:T],Bin);  # the indicator of departure
        @variable(m,Z[FSet1,0:T],Bin);  # the indicator of cancellation
        @variable(m,L[FSet,0:T],Bin);    # the indicator of arrival
        @variable(m,Y[FSet,0:T],Bin);    # the indicator of landing
        @variable(m,E[FSet3,0:T],Bin);   # the indicator of taking off
        # set up the objective function
        @expression(m,gdpCost,sum{sum{g[f,t]*(D[f,t] - D[f,t-1]),t in S[f]-N:T},f in FSet1});
        @expression(m,cancelCost,sum{sum{c[f,t]*(Z[f,t] - Z[f,t-1]), t in 1:T}, f in FSet1});
        @expression(m,airborneCost,sum{sum{a[f]*(L[f,t] - Y[f,t]) ,t in LC[f]:T} ,f in FSet});
        @expression(m,taxiCost,sum{sum{tc[f]*(E[f,t] - E[f,t-1]),t in TS[f]:T},f in FSet3});
        @objective(m,Min,gdpCost+cancelCost+airborneCost+taxiCost);
        # set up the constraints
        @constraint(m,mustLand1[f in FSet1], Y[f,T] + Z[f,T] == 1);
        @constraint(m,mustLand2[f in FSet2], Y[f,T] == 1);
        @constraint(m,mustTO[f in FSet3], E[f,T] == 1);
        @constraint(m,noCancel[f in FSet1, t = 1:T], Z[f,t] + D[f,t] <= 1);
        @constraint(m,landAfter[f = FSet, t = 1:T], Y[f,t] <= L[f,t]);
        @constraint(m,planDept[f in FSet1, t = 1:T-N], X[f,t] == D[f,t+N]);
        @constraint(m,planLand[f in FSet1, t = 1:T-tau[f]], D[f,t] == L[f,t + tau[f]]);
        # here 2000 is a dummy parameter and it will be substituted in the main program
        @constraint(m,capArr[t = TSet], sum{Y[f,t] - Y[f,t-1],f in FSet} <= 2000);
        @constraint(m,capDept[t = TSet], sum{E[f,t] - E[f,t-1],f in 1:F3} <= 2000);
        @constraint(m,capTot[t = TSet], sum{Y[f,t] - Y[f,t-1],f in FSet} + sum{E[f,t] - E[f,t-1],f in 1:F3} <= 2000);
        @constraint(m,propX[f in FSet1, t = 1:T], X[f,t] >= X[f,t-1]);
        @constraint(m,propY[f in FSet, t = 1:T], Y[f,t] >= Y[f,t-1]);
        @constraint(m,propL[f in FSet, t = 1:T], L[f,t] >= L[f,t-1]);
        @constraint(m,propZ[f in FSet1, t = 1:T], Z[f,t] >= Z[f,t-1]);
        @constraint(m,F2Arr[f in FSet2, t = LC[f]:T], L[f,t] == 1);
        @constraint(m,F2noArr[f in FSet2, t = 0:LC[f]-1], L[f,t] == 0);
        @constraint(m,F3noDept[f in FSet3, t = 0:TS[f]-1], E[f,t] == 0);
        # set up auxiliary constraints
        # cannot take off before S[i]
        @constraint(m,noTakeoff[f in FSet1, t = 1:S[f]-1], D[f,t] == 0);
        # initial condition
        @constraints(m,begin
            initX[f in FSet1], X[f,0] == 0
            initY[f in FSet], Y[f,0] == 0
            initZ[f in FSet1], Z[f,0] == 0
            end);

        push!(mfList,m);
    end
    return mfList
end
