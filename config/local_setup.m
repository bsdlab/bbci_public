function local_setup()
%local_setup Sets local paths

global PROJECT_SETUP

% setup:
% `cp local_setup.m.example local_setup.m` 
% and adapt the latter to your personal environment 

PROJECT_SETUP.BBCI_DIR = '~/repos/bbci_fork/';
PROJECT_SETUP.PYFF_DIR = '~/repos/pyff/';
PROJECT_SETUP.TCP_UDP_DIR = '~/software/tcp_udp_ip/';
PROJECT_SETUP.VCO_DATA_DIR = '~/local_data/kitti';
PROJECT_SETUP.BBCI_DATA_DIR = fullfile(getenv('HOME'), 'local_data', 'bbci');
PROJECT_SETUP.BBCI_TMP_DIR = fullfile(getenv('HOME'), 'local_data', 'tmp');
PROJECT_SETUP.SCREEN_SIZE = [1400, 600];
PROJECT_SETUP.SCREEN_POSITION = [250, 150];

% Settings for systems with actual experiment hardware
PROJECT_SETUP.HARDWARE_AVAILABLE = false;
PROJECT_SETUP.PARALLEL_PORT_ADDRESS = '0xD050';
% should be committed to repo in directory experiment_scripts/extra_files
PROJECT_SETUP.BV_WORKSPACE_FILE_NAME = 'somefile.rwksp';
PROJECT_SETUP.BV_RECORDER_EXECUTABLE = 'notify-send "starting recorder"';