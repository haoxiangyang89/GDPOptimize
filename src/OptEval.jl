# this is the code to calculate the costs of real operation
using DataFrames,RDatasets,PyPlot;

function generateCost(T,FSG,FSG3)
    g = Dict();
    a = Dict();
    c = Dict();
    tc = Dict();
    cz = Dict();
    r = Dict();
    # this is the functiono that generates all the costs
    for f in FSG
        r[f] = 40;
        # generate the ground delay cost and airborne delay cost for planes that have not been cleared
        a[f] = 5;
        c[f] = 20;
        for t in 1:T
            g[f,t] = 1.35^(t);
        end
    end
    # generate the taxi-out cost for planes to depart
    for f in FSG3
        cz[f] = 20;
        for t in 1:T
            tc[f,t] = 1.5^(t - TS[f]);
        end
    end
    return g,a,c,tc,cz,r
end

function costEval(ArrAdd,DeptAdd)
    ArrInfo,Arrtitle = readdlm(ArrAdd,',',header = true);
    flCarrInd,flNoInd,DepDelayInd,TXOutInd,CElapseInd,AElapseInd,cancelInd,divertedInd =
        indexin(["UNIQUE_CARRIER","FL_NUM","DEP_DELAY","TAXI_OUT","CRS_ELAPSED_TIME","ACTUAL_ELAPSED_TIME","CANCELLED","DIVERTED"],Arrtitle);

    DeptInfo,Depttitle = readdlm(DeptAdd,',',header = true);

    F = size(ArrInfo)[1];
    F3 = size(DeptInfo)[1];
    AFlightID = [string(ArrInfo[i,flCarrInd],"_",ArrInfo[i,flNoInd]) for i in 1:F];
    DFlightID = [string(DeptInfo[i,flCarrInd],"_",DeptInfo[i,flNoInd]) for i in 1:F3];
    g,a,c,tc,cz,r = generateCost(48,1:F,1:F3);
    gdpCost = 0;
    abCost = 0;
    taxiCost = 0;
    cancelCost = 0;
    rerouteCost = 0;

    for i in 1:F
        if ArrInfo[i,cancelInd] == 1
            # calculate the gdp cost
            cancelCost += c[i];
        elseif ArrInfo[i,divertedInd] == 1
            # calculate the reroute cost
            rerouteCost += r[i];
        else
            ngdp = max(round(Int64,ArrInfo[i,DepDelayInd]/30),0);
            if ngdp <= 10
                for j in 1:ngdp
                    gdpCost += g[i,j];
                end
                # calculate the airborne cost
                abCost += a[i]*max(round(Int64,(ArrInfo[i,AElapseInd] - ArrInfo[i,CElapseInd])/30),0);
            end
        end
    end
    for i in 1:F3
        # calculate the cancellation cost
        if DeptInfo[i,cancelInd] == 1
            cancelCost += cz[i];
        elseif DeptInfo[i,divertedInd] == 0
            # calculate the taxi cost
            ntaxi = max(floor(Int64,DeptInfo[i,TXOutInd]/30),0);
            for j in 1:ntaxi
                taxiCost += g[i,j];
            end
        end
    end
    println("Total Cost = ",gdpCost+abCost+cancelCost+rerouteCost+taxiCost);
    println("GDP Cost = ",gdpCost);
    println("Airborne Cost = ",abCost);
    println("Taxi-out Cost = ",taxiCost);
    println("Cancellation Cost = ",cancelCost);
    println("Reroute Cost = ",rerouteCost);
end
