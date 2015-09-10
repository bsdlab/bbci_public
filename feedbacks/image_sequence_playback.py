#!/usr/bin/env python

# image_sequence_playback.py -

""" Pyff feedback for image sequence playback """

import logging
import os
import pygame
import sys
import time

import markers
import pygame_helpers
import seq_file_utils
from state_machine import StateMachineFeedback, StateOutput, FrameState
import vco_utils

class ImageSeqFeedback(StateMachineFeedback):
    """Feedback implementation for sequence playback
        
       Typical state transitions:
       "cmd" transitions means waiting for the corresponding state_command interaction signal
       "time" means the transition is automatically performed after playback/timeout

           [playback start]
               |
               v
        +->StandbyState
        |      | [cmd: start_preload]
        |      v
        |  BlockPreloadState
        |      | [cmd: start_playback]
        |      v
        +--SequencePlaybackState <-+
               | [time]            | [time]
               v                   |
           IntraBlockPauseState ---+
    """

    def start_state(self):
        """start in standby [usually until preload command] """
        return StandbyState(self)

    def _build_default_configuration(self):
        default_conf = super(ImageSeqFeedback, self)._build_default_configuration()
        default_conf.update({'sync_markers_enabled' : True,
                             #seconds between seqs in same block
                             'inter_sequence_delay': 3.0, #in seconds
                             'overlay_duration' : 1.0, #in seconds
                             'overlay_color': pygame.Color('black'),
                             'next_block_info' : [],
                             #minimal delay to wait before playback after receiving command
                             'playback_delay' : 1.0,
                             'log_prefix_block' : "defaultblock"
                            })
        return default_conf

    def _handle_config_param(self, name, value):
        """add special handling of block info"""
        if name == 'next_block_info':
            #should be a serialized list in the form [('/path/seqfile', 10)]
            str_value = value
            if isinstance(str_value, list):
                str_value = vco_utils.parse_matlab_char_array(str_value)
            #dangerous, but we expect to be in a trustworthy environment...
            new_value = eval(str_value.replace('\\', '\\\\')) #pylint: disable=eval-used
            if (isinstance(new_value, list)
                and isinstance(new_value[0], tuple)
                and isinstance(new_value[0][0], str) #filename
                and isinstance(new_value[0][1], int)): #fps
                self.config['next_block_info'] = new_value
                self.logger.info("updated block info to %s", new_value)
            else:
                self.logger.error("ignoring malformed block info %s", new_value)

        else:
            super(ImageSeqFeedback, self)._handle_config_param(name, value)


class StandbyState(FrameState):
    """ default screen, until receiving start_preload command"""
    def __init__(self, controller):
        super(StandbyState, self).__init__(controller)

    def _handle_state(self, screen):
        frame_markers = []
        if self._state_frame_count == 0:
            frame_markers.append(markers.technical['standby_start'])

        if "start_preload" in self._unhandled_commands:
            self._unhandled_commands.remove('start_preload')
            seq_fps_list = self.controller.config['next_block_info']
            if len(seq_fps_list) > 0:
                frame_markers.append(markers.technical['standby_end'])
                return StateOutput(frame_markers,
                                   BlockPreloadState(self.controller, seq_fps_list))
            else:
                self.logger.error("no sequences to preload, staying in standby")
        return StateOutput(frame_markers, self)


class IntraBlockPauseState(FrameState):
    """
       Pause between two sequences within the same block
    """
    def __init__(self, controller, delay_seconds, next_state):
        super(IntraBlockPauseState, self).__init__(controller)
        self._time_delay = delay_seconds
        self._next_state = next_state
        self._delay_frame_no = delay_seconds * self.controller.config['screen_fps']

    def _handle_state(self, screen):
        new_markers = []
        if self._state_frame_count == 0:
            new_markers.append(markers.technical['intra_block_pause_start'])

        pygame_helpers.draw_center_cross(screen)

        if self._state_frame_count < self._delay_frame_no:
            #still delaying
            #self.logger.debug("%d of %d frames elapsed, delaying", self._state_frame_count, self._delay_frame_no)

            return StateOutput(new_markers, self)
        else:
            new_markers.append(markers.technical['pre_seq_start'])
            return StateOutput(new_markers, self._next_state)


class SequencePlaybackState(FrameState):
    """ state for actual sequence playback
    all playback state (progress) is captured at this place
    After playback finishes, the follow-up state is either
     - an IntraBlockPauseState before the next sequence in the block
     - StandbyState if no more sequences in the block
    """

    def __init__(self, controller, seq_no, block_data):
        super(SequencePlaybackState, self).__init__(controller)
        self.seq_no = seq_no
        self.block_data = block_data
        self.seq_name, self.seq_fps = block_data.seq_fps_list[seq_no]
        self.seq_frame_count = len(self.block_data.image_seqs[self.seq_name])
        self._overlay_end_frame = -1


    def _handle_state(self, screen):
        assert self._state_frame_count < self.seq_frame_count
        new_markers = []
        conf = self.controller.config

        #-------
        #control
        trigger_overlay_controls = [ctrl for ctrl in self._unhandled_controls if 'trigger_overlay' in ctrl]
        if trigger_overlay_controls:
            for ctrl in trigger_overlay_controls:
                self._unhandled_controls.remove(ctrl)
            self._overlay_end_frame = self._state_frame_count + conf['overlay_duration'] * conf['screen_fps']

        
        #-------
        #markers
        if self._state_frame_count == 0:
            conf['screen_fps'] = self.seq_fps
            new_markers.append(markers.technical['seq_start'])

        frame_info = self.block_data.get_frame_info(self.seq_name,
                                                    self._state_frame_count)
        #add stimulus markers
        new_markers.extend([marker.value for marker in frame_info.marker_tuples])

        #add sync marker
        if conf['sync_markers_enabled'] and self._state_frame_count % 50 == 0:
            new_markers.append(markers.technical['sync_50_frames'])

        #---------
        #drawing
        frame_image = self.block_data.get_frame_image(self.seq_name, self._state_frame_count)
        pygame_helpers.draw_image(screen, frame_image)

        if conf['display_debug_information']:
            status = "Frame %d/%d" % (self._state_frame_count, self.seq_frame_count)
            pygame_helpers.display_message(screen, self.seq_name,
                                           pos=(20, 50), size=20)
            pygame_helpers.display_message(screen, status,
                                           pos=(20, 80), size=20)
            pygame_helpers.display_message(screen, ' '.join(frame_info.event_names),
                                           pos=(20, conf['screen_height'] - 60), size=20)
            marker_names = ' '.join([marker.name for marker in frame_info.marker_tuples])
            pygame_helpers.display_message(screen, marker_names,
                                           pos=(20, conf['screen_height'] - 30), size=20)


        #overlay
        if self._state_frame_count < self._overlay_end_frame:
            pygame_helpers.draw_interaction_overlay(screen, conf)


        #------------
        #state output
        if self._state_frame_count + 1 < self.seq_frame_count:
            return StateOutput(new_markers, self)
        else: #we're at the last frame of the sequence
            new_markers.append(markers.technical['seq_end'])
            if self.seq_no + 1 < len(self.block_data.seq_fps_list):
                next_playback_state = SequencePlaybackState(self.controller,
                                                            self.seq_no + 1,
                                                            self.block_data)
                next_state = IntraBlockPauseState(self.controller,
                                                  conf['inter_sequence_delay'],
                                                  next_playback_state)
            else: #we're done with the last sequence of the block
                next_state = StandbyState(self.controller)
            return StateOutput(new_markers, next_state)


class BlockPreloadState(FrameState):
    """state that loads all images into memory (list supplied in init)
        playback is initiated after both preloading is complete and a
        'start_playback' command has been received
    """
    def __init__(self, controller, seq_fps_list, auto_play=False):
        super(BlockPreloadState, self).__init__(controller)
        self.seq_fps_list = seq_fps_list
        self.block_data = BlockData(seq_fps_list)
        self.cache_batch_size = 5
        self.caching_complete = False
        self._earliest_playback_start = sys.maxint #for delay after command
        if auto_play:
            self._unhandled_commands.append('start_playback')

    def _load_images_blocking(self):
        """initiates and updates caching"""
        if self.block_data.caching_progress() < 1:
            #load approx for 100ms
            start_time = time.clock()
            while time.clock() - start_time < 0.1:
                self.block_data.cache_batch(self.cache_batch_size)

    def _handle_state(self, screen):
        new_markers = []
        config = self.controller.config

        #------
        #screen
        if config['display_debug_information']:
            if self.caching_complete:
                status = "cached"
            else:
                status = "caching..."
            pygame_helpers.display_message(screen, status, pos=(20, 50), size=20)
            progress = "%1.1f %%" % (self.block_data.caching_progress() * 100)
            pygame_helpers.display_message(screen, progress,
                                           pos=(20, 80), size=20)

        pygame_helpers.draw_center_cross(screen)

        #check if we received playback command
        if "start_playback" in self._unhandled_commands:
            delay_framelength = config['playback_delay'] * config['screen_fps']
            after_delay = self._state_frame_count + delay_framelength
            self._earliest_playback_start = min(self._earliest_playback_start, after_delay)

        #do actual work
        self._load_images_blocking()
        #control state
        if self.block_data.caching_progress() == 1: #updated since last check
            if not self.caching_complete: #first check after completion -> marker
                new_markers.append(markers.technical['preload_completed'])
            self.caching_complete = True
        if self.caching_complete and self._state_frame_count >= self._earliest_playback_start:
            new_markers.append(markers.technical['pre_seq_start'])
             #logging/serialization of config
            conf_dump_file = os.path.join(config['log_dir'],
                                          config['log_prefix_block'] + "_config.p")
            vco_utils.dump_settings(self.controller, conf_dump_file)
            self.logger.info("starting block playback, git code revision %s", config['git_revision_info'])
            return StateOutput(new_markers,
                               SequencePlaybackState(self.controller, 0, self.block_data))
        else:
            return StateOutput(new_markers, self)



class BlockData(object):
    """ data object for loading sequence files and caching images
        note that behavior of accessing images during caching is undefined/might raise exceptions
    """
    def __init__(self, seq_fps_list):
        self._cache = {} #NOT thread-safe
        self._caching_task = None
        self.logger = logging.getLogger("vco.technical")
        self.seq_fps_list = seq_fps_list
        self.image_seqs = {}
        for seq_file, _ in seq_fps_list:
            image_seq = seq_file_utils.load_seq_file(seq_file)
            self.image_seqs[seq_file] = image_seq
        self._all_files = [frame.file_name for image_seq in self.image_seqs.values() for frame in image_seq]
        self._current_cache_index = 0

    def cache_batch(self, batch_size):
        """ reads the next batch_size elements into memory (if available)"""
        range_end = min(self._current_cache_index + batch_size, len(self._all_files))
        for image_idx in range(self._current_cache_index, range_end):
            filename = self._all_files[image_idx]
            #self.logger.debug("loading image %d: %s", image_idx, filename)
            self._cache[filename] = pygame_helpers.load_image(filename)
        self._current_cache_index = range_end - 1

    def caching_progress(self):
        """return number of cached images. treat with caution due to missing thread-safety"""
        return 1.0 * len(self._cache) / len(self._all_files)

    def get_frame_info(self, seq_file, index):
        """return the values of all markers in the given frame"""
        return self.image_seqs[seq_file][index]

    def get_frame_image(self, seq_file, index):
        """returns frame as a pygame image; loads it from disk if necessary"""
        filename = self.image_seqs[seq_file][index].file_name
        if filename not in self._cache:
            self._cache[filename] = pygame_helpers.load_image(filename)
        return self._cache[filename]


def _run_example():
    """run feedback for test purposes"""
    logging.getLogger().addHandler(logging.StreamHandler())
    logging.getLogger().setLevel(logging.INFO)
    feedback = ImageSeqFeedback()
    feedback.on_init()
    feedback.udp_markers_host = '127.0.0.1'  #pylint: disable=attribute-defined-outside-init
    feedback.udp_markers_port = 12344 #pylint: disable=attribute-defined-outside-init
    feedback._handle_config_param('display_debug_information', True)
    seq_fps_list_str = '[("/mnt/blbt-fs1/backups/cake-hk1032/data/kitti/seqs/seq03_kelterstr.txt", 10)]'
    param_block_seq_file_fps_list = [ord(c) for c in seq_fps_list_str]  #pylint: disable=attribute-defined-outside-init
    feedback._handle_config_param('next_block_info', param_block_seq_file_fps_list) #pylint: disable=protected-access
    parsed_block_info = feedback.config['next_block_info']
    #instead of command, we force the state directly
    feedback._cur_state = BlockPreloadState(feedback, parsed_block_info, auto_play=True)#pylint: disable=attribute-defined-outside-init
    feedback.on_play()

if __name__ == "__main__":
    _run_example()
