%% Run experiment with BV hardware
clear, clc, close all;

% path config, start up bbci toolbox
project_setup();
% config for this experimental run
experiment_config();

%% Start feedback and BV controller
pyff_start_feedback_controller()
% workaround: for some reason the socket is not initialized until the first
% pyff_sendUdp call from the main file, despite the socket being persistent
pyff_sendUdp('interaction-signal', 'command','stop');

system([PROJECT_SETUP.BV_RECORDER_EXECUTABLE ' &'])

pause(3);

%% Set feedback parameters
% sequence file and FPS are added within the for loop
fbsettings = pyff_build_parameters();

sequences = [...
    EXPERIMENT_CONFIG.complexSeqs; ...
    EXPERIMENT_CONFIG.simpleSeqs];
% sequences = {
%     'seq_c09_1-weiherfelda-mod5-v2.txt'  8
%     'seq_c06_1-kelterstr-mod3-v1.txt'   8
%     };



seqOrder = 1:size(sequences, 1);
if EXPERIMENT_CONFIG.sequences.randomize
    seqOrder = randperm(size(sequences, 1));
end

%% loop over sequences
for i = seqOrder
    seqFileName = sequences{i,1};
    seqFPS = sequences{i,2};
    
    fbsettings.param_image_seq_file = fullfile(PROJECT_SETUP.SEQ_DATA_DIR, seqFileName);
    if exist(fbsettings.param_image_seq_file, 'file') == 0
        % sequence file not accessible, so we don't bother starting the feedback
        fprintf(['Cannot access %s, aborting!\n'], fbsettings.param_image_seq_file)
        break;
    end
    fbsettings.FPS = seqFPS;
    fbsettings.param_logging_prefix = [EXPERIMENT_CONFIG.filePrefix '_' seqFileName];
    fbOpts = fieldnames(fbsettings);
    
    fprintf('Sending feedback parameters...')
    for optId = 1:length(fbOpts),
        pyff_sendUdp('interaction-signal', fbOpts{optId}, getfield(fbsettings, fbOpts{optId})); %#ok<GFLD>
    end
    fprintf(' Done!\n')
    
    
    %% Loading data.
    
    fprintf([' Next sequence file ', seqFileName, '\n'])
    if (input('Enter q to quit, anything else to continue...\n', 's') == 'q')
        break
    end
    
    
    
    
    %% setup recording
    % Setup bbci toolbox parameters
    
    bbci = bbci_setup_bv_recording(seqFileName);
    bvr_sendcommand('stoprecording');
    bbci_acquire_bv('close')
    bvr_sendcommand('loadworkspace', fullfile(PROJECT_SETUP.EXPERIMENT_SCRIPTS_DIR, 'extra_files', PROJECT_SETUP.BV_WORKSPACE_FILE_NAME))
    
    bvr_sendcommand('viewsignals')
    
    
    %% Run feedback
    pyff_sendUdp('interaction-signal', 'command','play');
    
    
    data = bbci_apply(bbci);
    
    %% Stop!
    pyff_sendUdp('interaction-signal', 'command','stop');
    
    if EXPERIMENT_CONFIG.validation.show_validation_stats
        validation_stats(data)
    end
    
end




%% close
pyff_sendUdp('interaction-signal', 'command','close');
pyff_sendUdp('interaction-signal', 'command','quitfeedbackcontroller');
pyff_sendUdp('close');
disp('UDP connection successfully closed')

