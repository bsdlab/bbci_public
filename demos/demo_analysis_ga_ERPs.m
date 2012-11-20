files = {'VPibv_10_11_02\calibration_CenterSpellerMVEP_VPibv',
  'VPibq_10_09_24\calibration_CenterSpellerMVEP_VPibq',
  'VPiac_10_10_13\calibration_CenterSpellerMVEP_VPiac',
  'VPibs_10_10_20\calibration_CenterSpellerMVEP_VPibs',
  'VPibt_10_10_21\calibration_CenterSpellerMVEP_VPibt'};
  
nsub = length(files);
for isub = 1:nsub
  file = files{isub};
  %% Load data
  hdr= file_readBVheader(file);
  Wps= [42 49]/hdr.fs*2;
  [n, Ws]= cheb2ord(Wps(1), Wps(2), 3, 40);
  [filt.b, filt.a]= cheby2(n, 50, Ws);
  [cnt, mrk_orig]= file_readBV(file, 'Fs',100, 'Filt',filt);

  %% Marker struct
  stimDef= {[31:46], [11:26];
            'target','nontarget'};
  mrk= mrk_defineClasses(mrk_orig, stimDef);

  %% Re-referencing to linked-mastoids
  A= eye(length(cnt.clab));
  iA1= util_chanind(cnt.clab,'A1');
  if isempty(iA1)
      iA1= util_chanind(cnt.clab,'A2');
  end
  A(iA1,:)= -0.5;
  A(:,iA1)= [];
  cnt= proc_linearDerivation(cnt, A);

  %% Electrode Montage
  grd= sprintf(['scale,_,F5,F3,Fz,F4,F6,_,legend\n' ...
                'FT7,FC5,FC3,FC1,FCz,FC2,FC4,FC6,FT8\n' ...
                'T7,C5,C3,C1,Cz,C2,C4,C6,T8\n' ...
                'P7,P5,P3,P1,Pz,P2,P4,P6,P8\n' ...
                'PO9,PO7,PO3,O1,Oz,O2,PO4,PO8,PO10']);
  mnt= mnt_setElectrodePositions(cnt.clab);
  mnt= mnt_setGrid(mnt, grd);

  % Define some settings
  disp_ival= [-200 1000];
  ref_ival= [-200 0];
  crit_maxmin= 70;
  crit_ival= [100 800];
  crit_clab= {'F9,z,10','AF3,4'};
  clab= {'Cz','PO7'};
  colOrder= [1 0 1; 0.4 0.4 0.4];

  % Apply highpass filter to reduce drifts
  b= procutil_firlsFilter(0.5, cnt.fs);
  cnt= proc_filtfilt(cnt, b);

  % Artifact rejection based on variance criterion
  %mrk= reject_varEventsAndChannels(cnt, mrk, disp_ival, 'verbose', 1);

  % Segmentation
  epo= proc_segmentation(cnt, mrk, disp_ival);

  % Artifact rejection based on maxmin difference criterion on frontal chans
  [epo iArte] = proc_rejectArtifactsMaxMin(epo, crit_maxmin, 'Clab',crit_clab, ...
                                  'Ival',crit_ival, 'Verbose',1);

  % Baseline subtraction, and calculation of a measure of discriminability
  epo= proc_baseline(epo, ref_ival);

  epos_av{isub} = proc_average(epo, 'Stats', 1);
  
  % three different but almost equivalent ways to make statistics about class differences
  epos_diff{isub} = proc_classmeanDiff(epo, 'Stats', 1);
  epos_r{isub} = proc_rSquareSigned(epo, 'Stats', 1);
  epos_auc{isub} = proc_aucValues(epo, 'Stats', 1);

end

% grand average
epo_av = proc_grandAverage(epos_av, 'Average', 'INVVARweighted', 'Stats', 1, 'Bonferroni', 1, 'Alphalevel', 0.01);
epo_r = proc_grandAverage(epos_r, 'Average', 'INVVARweighted', 'Stats', 1, 'Bonferroni', 1, 'Alphalevel', 0.01);
epo_diff = proc_grandAverage(epos_diff, 'Average', 'INVVARweighted', 'Stats', 1, 'Bonferroni', 1, 'Alphalevel', 0.01);
epo_auc = proc_grandAverage(epos_auc, 'Average', 'INVVARweighted', 'Stats', 1, 'Bonferroni', 1, 'Alphalevel', 0.01);

mnt = mnt_setElectrodePositions(epo_av.clab);
mnt= mnt_setGrid(mnt, grd);

% Select some discriminative intervals, with constraints to find N2, P2, P3 like components.
constraint= ...
      {{-1, [100 300], {'I#','O#','PO7,8','P9,10'}, [50 300]}, ...
       {1, [200 350], {'P3-4','CP3-4','C3-4'}, [200 400]}, ...
       {1, [400 500], {'P3-4','CP3-4','C3-4'}, [350 600]}};
[ival_scalps, nfo]= ...
    select_time_intervals(epo_r, 'Visualize', 0, 'VisuScalps', 1, ...
                          'Title', util_untex(file), ...
                          'Clab',{'not','E*'}, ...
                          'Constraint', constraint);
%printFigure('r_matrix', [18 13]);
ival_scalps= visutil_correctIvalsForDisplay(ival_scalps, 'fs',epo.fs);

% plot classwise grand-average ERPs
fig_set(1);
H= plot_scalpEvolutionPlusChannel(epo_av, mnt, clab, ival_scalps, defopt_scalp_erp, ...
                             'ColorOrder',colOrder);
grid_addBars(epo_r);
%printFigure(['erp_topo'], [20  4+5*size(epo.y,1)]);

% plot difference of the class means
fig_set(2, 'shrink',[1 2/3]);
plot_scalpEvolutionPlusChannel(epo_diff, mnt, clab, ival_scalps, defopt_scalp_r);
%printFigure(['erp_topo_r'], [20 9]);

% plot signed log10 p-values of the null hypothesis
% that the difference of the class means is zero
% interpretation: abs(sgnlogp) > 1   <-->  p < 0.1
%                 abs(sgnlogp) > 2   <-->  p < 0.01
%                 abs(sgnlogp) > 3   <-->  p < 0.001 , and so on
fig_set(3, 'shrink',[1 2/3]);
epo_diff_sgnlogp = epo_diff;
epo_diff_sgnlogp.x = epo_diff_sgnlogp.sgnlogp;
epo_diff_sgnlogp.yUnit = 'sgnlogp';
plot_scalpEvolutionPlusChannel(epo_diff_sgnlogp, mnt, clab, ival_scalps, defopt_scalp_r);
%printFigure(['erp_topo_r'], [20 9]);

% now plot differences again, with all insignificant results set to zero
epo_diff.x = epo_diff.x.*epo_diff.sigmask;
fig_set(4, 'shrink',[1 2/3]);
plot_scalpEvolutionPlusChannel(epo_diff, mnt, clab, ival_scalps, defopt_scalp_r);
