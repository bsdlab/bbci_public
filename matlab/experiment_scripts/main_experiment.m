%% Run experiment
%delete everything, including UDP connections and persistent variables
clear all; %#ok<CLSCR>
clc, close all;

%% init global variables PROJECT_SETUP and EXPERIMENT_CONFIG
% path config, start up bbci toolbox
init_experiment_setup();
% config for this experimental run
experiment_config();

%% Start feedback and BV controller
pyff_start_feedback_controller()
% workaround: for some reason the socket is not initialized until the first
% pyff_sendUdp call from the main file, despite the socket being persistent
pyff_sendUdp('interaction-signal', 'command','stop');

if PROJECT_SETUP.HARDWARE_AVAILABLE
    system([PROJECT_SETUP.BV_RECORDER_EXECUTABLE ' &'])
    pause(3);
    bvr_sendcommand('stoprecording');
    bbci_acquire_bv('close')
    bvr_sendcommand('loadworkspace', fullfile(PROJECT_SETUP.CONFIG_DIR, PROJECT_SETUP.BV_WORKSPACE_FILE_NAME))
    bvr_sendcommand('viewsignals')
end

%save config
if ~exist(EXPERIMENT_CONFIG.recordDir, 'dir')
    mkdir(EXPERIMENT_CONFIG.recordDir)
end
save(fullfile(EXPERIMENT_CONFIG.recordDir, 'experiment_config.mat'), 'EXPERIMENT_CONFIG');

%technically, we start playing here, although the feedback will still be in
%standby
pyff_send_parameters(EXPERIMENT_CONFIG.block_structure(false,:), 'standby'); %send base parameters with empty block
pyff_sendUdp('interaction-signal', 'command','play');

%% loop over blocks
for block_no = 0:(EXPERIMENT_CONFIG.block_count - 1)
    block_rows_sel = EXPERIMENT_CONFIG.block_structure.blockNo == block_no;
    current_block = EXPERIMENT_CONFIG.block_structure(block_rows_sel, :);
    
    block_name = sprintf('block%02d', block_no);

    
    %% Loading data.
    pyff_send_parameters(current_block, block_name);
    pyff_sendUdp('interaction-signal', 'state_command','start_preload');
    fprintf('Preloading...')
%     wait_for_marker(EXPERIMENT_CONFIG.markers.technical.preload_completed)
    stimutil_waitForMarker(bbci_setup('loading'), EXPERIMENT_CONFIG.markers.technical.preload_completed)
    fprintf('complete\n')

    fprintf([' Next block: ', block_name, '\n'])
    for seqIdx = 1:size(current_block, 1)
        fprintf(['  ' current_block.seqName{seqIdx} '\n'])
    end

    if (input('Enter q to quit, anything else to continue...\n', 's') == 'q')
        break
    end
    
    %% setup recording
    % Setup bbci toolbox parameters
    bbci = bbci_setup(block_name);
    %configure brain vision recorder
    if PROJECT_SETUP.HARDWARE_AVAILABLE
        bvr_sendcommand('stoprecording');
        bbci_acquire_bv('close')
        bvr_sendcommand('loadworkspace', fullfile(PROJECT_SETUP.CONFIG_DIR, PROJECT_SETUP.BV_WORKSPACE_FILE_NAME))
        
        bvr_sendcommand('viewsignals')
    end
    
    %% Run!
    pyff_sendUdp('interaction-signal', 'state_command','start_playback');
    fprintf('Sent play signal\n')
    
    data = bbci_apply(bbci);

    if ~any(data.marker.desc == EXPERIMENT_CONFIG.markers.technical.seq_start)
        fprintf('%s\n', ['Playback did not start, consult log in ' EXPERIMENT_CONFIG.feedbackLogDir])
    end

    %% some validation
    if EXPERIMENT_CONFIG.validation.show_validation_stats
        marker_stats(data.marker)
    end
    
end


pyff_sendUdp('interaction-signal', 'command','stop');


%% close
pyff_sendUdp('interaction-signal', 'command','close');
pyff_sendUdp('interaction-signal', 'command','quitfeedbackcontroller');
pyff_sendUdp('close');
disp('UDP connection successfully closed')

