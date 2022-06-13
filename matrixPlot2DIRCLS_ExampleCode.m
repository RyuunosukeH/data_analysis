load('testDataCLS.mat');

%%
r1 = [2330 2345];
r3 = r1;
cpData = cropData(zzzz_data, r1, r3);

f = prepareGlobalFitData(cpData);
dm = [5 6];
matrixPlot2DIRCLS(f, cpData(1).w1, cpData(1).w3, [cpData(:).t2]./1000, dm, CLS_zzzz, maxMatrix_zzzz, 'fignum', 1)