%
% my_second_script_good_b
%
close all;
clear all;
clc;
%
% read data from file 'assignment_8_Data.txt'
%
%A = dlmread('assignment_8_Data.txt','|',[2,0,100,1]);
A = readmatrix("assignment_8_Data.txt",'Delimiter','|');
%
dayNumber = A(1:1:99,1);
cost = A(1:1:99,2);
%
% Plot cost in blue line and mark the data points with an 'x'
%
%
plot(cost,'rs-','MarkerFaceColor','b','LineWidth',2);
ylabel('Cost');         % label x-axis
xlabel('Days')          % label y-axis
title('Cost vs Days Plot');     % title of plot
legend('cost of the tires','Location', 'south');    % legend helps you define what a line is
grid minor;
%
cost_min = min(cost)
cost_max = max(cost)
cost_mean = mean(cost)
cost_median = median(cost)
total_sum_cost = sum(cost)
standard_deviation_cost = std(cost)
%
disp(['>>> END of my_second_script_good.m <<<']);

