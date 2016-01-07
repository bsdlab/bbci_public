function mrk= mrkodef_relax(mrko)

stimDef= {1, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20;
          'stop', ...
          'mc_left', ...                    
          'mc_right', ...                   
          'mc_foot', ...                    
          'look_center', ...                  
          'look_left', ...                    
          'look_right', ...                   
          'look_up', ...                      
          'look_down', ...                    
          'blink', ...                   
          'press_your_eyelids_shut', ... 
          'eyes_closed', ...             
          'eyes_open', ...               
          'swallow', ...                 
          'press_tongue_to_the_roof_of_your_mouth', ...
          'lift_shoulders', ...
          'clench_teeth',  ... 
          'over'}; 
%          'maximum_compression', ...     %% corresponds to #02
%          'look', ...                    %% corresponds to #06

miscDef= {252, 253;
          'start', 'end'};
mrk= mrk_defineClasses(mrko, stimDef);
mrk.misc= mrk_defineClasses(mrko, miscDef);
