function readIn(N,startT,endT,capAddress,capProbAdd,ArrAdd,DeptAdd)
    # check if (endT - startT) equals to T, startT and endT in format of time
    T = timeDiff(startT,endT);

    # input the capacity information
    capD = capInput(T,capAddress,capProbAdd);

    # input the arrival/departure information
    flightD = arrdeptInput(T,startT,endT,ArrAdd,DeptAdd,N);

    # input the cost information
    costD = costInput(T,flightD);

    return T,capD,flightD,costD;
end
