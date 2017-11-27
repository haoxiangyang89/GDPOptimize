# Plot the graphs for the GDP problem

# plot the comparison between the capacity of 01/10/2011 and 05/04/2014
compData <- read.csv("/Users/haoxiangyang/Desktop/Git/GDPOptimize/capacity_showcase.csv");
plot(compData$Time,compData$X0504Dept,type = "l",col = "#006400",lwd = 1.5,xlab = "Time Period",ylab = "No. of Departures",main = "Departures Comparison");
lines(compData$Time,compData$X0110Dept,lwd = 1.5,col = "#9900D3");
legend("topleft",
       legend = c("2014-05-04","2011-01-10"),
       col = c("#006400","#9900D3"),
       bty = "n",
       pch = 15
);

plot(compData$Time,compData$X0504Arr,type = "l",col = "#006400",lwd = 1.5,xlab = "Time Period",ylab = "No. of Arrivals",main = "Arrivals Comparison");
lines(compData$Time,compData$X0110Arr,lwd = 1.5,col = "#9900D3");
legend("topleft",
       legend = c("2014-05-04","2011-01-10"),
       col = c("#006400","#9900D3"),
       bty = "n",
       pch = 15
);

plot(compData$Time,compData$X0504Tot,type = "l",col = "#006400",lwd = 1.5,xlab = "Time Period",ylab = "No. of Actions",main = "Departures+Arrivals Comparison");
lines(compData$Time,compData$X0110Tot,lwd = 1.5,col = "#9900D3");
legend("topleft",
       legend = c("2014-05-04","2011-01-10"),
       col = c("#006400","#9900D3"),
       bty = "n",
       pch = 15
);
