function [p]=exp_Immuno(subject, phase)

%[p]=exp_FearGen_ForAll(subject,phase,csp,PainThreshold)
%   To do before you start:
%   Set the baselocation for the experiment in SetParams around line 420:
%   p.path.baselocation variable. this location will be used to save
%   the experiment-related data for the current subject.
%
%   Adapted from Selim Onats scripts.

debug   = 1; %debug mode => 1: transparent window enabling viewing the background.
NoEyelink = 1; %is Eyelink wanted?

%replace parallel port function with a dummy function
if ~IsWindows
    %OUTP.m is used to communicate with the parallel port, mainly to send
    %triggers to the physio-computer or Digitimer device (which is used to give
    %shocks). OUTP is a cogent function, so it only works with Windows. In
    %Unix the same functionality can also be obtained with PTB, but it is not
    %coded in this program yet. So to communicate via the parallel port, there
    %are two options: 1/install cogent + outp, or 2/ use equivalent of OUTP
    %in PTB. This presentation will now replace the OUTP.m function with
    %the following code, which simply does nothing but allows the program
    %run.
    
    outp = @(x,y) 1;
end

if nargin ~= 2
    fprintf('Wrong number of inputs\n');
    return
end

commandwindow;%focus on the command window, so that output is not written on the editor
%clear everything
clear mex global functions;%clear all before we start.

if IsWindows%clear cogent if we are in Windows and rely on Cogent for outp.
    cgshut;
    global cogent;
end

%%%%%%%%%%%load the GETSECS mex files so call them at least once
GetSecs;
WaitSecs(0.001);


el        = [];%eye-tracker variable
p         = [];%parameter structure that contains all info about the experiment.


SetParams;%set parameters of the experiment
SetPTB;%set visualization parameters.

%%
%init all the variables
t                         = [];
nTrial                    = 0;

%Time Storage
TimeEndStim               = [];
TimeTrackerOff            = [];
TimeCrossOn               = [];
p.var.event_count         = 0;

%% Load stimulus sequence
sequences = load('stimulus_sequences.mat');
sequences = sequences.sequences;
sequence = sequences{subject}{phase}



%% Setup reward probabilities: Fixed across subjects
reward_probabilities = [0.8, 0.5, 0.2];

%%

% The experiment has six phases:
% 1 - training day one
% 2 - fMRI day one
% 3 - training day two
% 4 - fMRI day two
% 5 - training day three
% 6 - fMRI day three

%% Training
if mod(phase,2) == 1
    p.mrt.dummy_scan = 0 ; %for the training we don't want any pulses
    p.phase = phase;
    for block = 1:7
        p.sequence = sequence(block);
        p.block = block;
        ExperimentBlock(p);
    end    
%% fMRI
elseif mod(phase, 2) == 0
    % Vormessung
    p.phase = phase;
    k = 0;
    while ~(k == p.keys.el_calib);
        pause(0.1);
        fprintf('Experimenter!! press V key when the vormessung is finished.\n');
        [~, k] = KbStrokeWait(p.ptb.device);
        k = find(k);
    end
    fprintf('Continuing...\n');
    %%
    p.block = 1;
    Retinotopy;
    if phase==2
        p.block = 2;
        Retinotopy
    end
    p.block = 3;
    p.sequence = sequence(1);
    ExperimentBlock(p);
    block = 4;
    while p.block <= 10         
        p.block = block;
        p.sequence = sequence(block-3);
        block = block+1;
        QuadrantLoc(p);        
        p.block = block;
        p.sequence = sequence(block-3);
        ExperimentBlock(p);
        block = block+1;
    end
    WaitSecs(2.5);
    
end

%get the eyelink file back to this computer
StopEyelink(p.path.edf);
%trim the log file and save
p.out.log = p.out.log(sum(isnan(p.out.log),2) ~= size(p.out.log,2),:);
%shift the time so that the first timestamp is equal to zero
p.out.log(:,1) = p.out.log(:,1) - p.out.log(1);
p.out.log      = p.out.log;%copy it to the output variable.
save(p.path.path_param,'p');
%
%move the file to its final location.
movefile(p.path.subject,p.path.finalsubject);
%close everything down
cleanup;


    function ExperimentBlock(p)
        KbQueueStop(p.ptb.device);
        KbQueueRelease(p.ptb.device);
        
        %Enter the presentation loop and wait for the first pulse to
        %arrive.
        %wait for the dummy scans
        p = InitEyeLink(p);        
        CalibrateEL;    
        KbQueueCreate(p.ptb.device);%, p.ptb.keysOfInterest);%default device.
        KbQueueStart(p.ptb.device)
        KbQueueFlush(p.ptb.device)
        
        [secs] = WaitPulse(p.keys.pulse,p.mrt.dummy_scan);%will log it        
        WaitSecs(.05);
        
        
        Eyelink('StartRecording');
        WaitSecs(0.01);           
        
        Eyelink('Message', sprintf('SUBJECT %d', p.subject));
        Eyelink('Message', sprintf('PHASE %d', p.phase));
        Eyelink('Message', sprintf('BLOCK %d', p.block));
        
        TimeEndStim     = secs(end)- p.ptb.slack;%take the first valid pulse as the end of the last stimulus.
        for trial  = 1:size(p.sequence.stim, 2);            
            %Get the variables that Trial function needs.
            stim_id      = p.sequence.stim(trial);
            RP           = p.sequence.reward_probability(trial);
            ISI          = p.sequence.isi(trial);
            
            OnsetTime     = TimeEndStim + ISI;
            fprintf('%d of %d, S: %i, R: %i, ISI: %2.2f, OnsetTime: %2.2f secs, Block: %i \n',...
                trial, size(p.sequence.stim, 2), stim_id, RP, ISI, OnsetTime, p.block);
            
            %Start with the trial, here is time-wise sensitive must be optimal
            [TimeEndStim] = Trial(trial, OnsetTime, stim_id, RP, p.block, p.phase);
            
            fprintf('OffsetTime: %2.2f secs, Difference of %2.2f secs\n', TimeEndStim, TimeEndStim-OnsetTime);
            
            [keycode, secs] = KbQueueDump;%this contains both the pulses and keypresses.
            if numel(keycode)
                %log everything but "pulse keys" as pulses, not as keypresses.
                pulses = (keycode == KbName(p.keys.pulse));

                if any(~pulses);%log keys presses if only there is one
                    Log(secs(~pulses), 1000,keycode(~pulses), p.phase, p.block);
                end
                if any(pulses);%log pulses if only there is one
                    Log(secs(pulses), 0, keycode(pulses), p.phase, p.block);
                end
            end
            
        end
        %wait 6 seconds for the BOLD signal to come back to the baseline...                
        if mod(p.phase, 2) == 0
            WaitPulse(p.keys.pulse, p.mrt.dummy_scan);%
            fprintf('OK!! Stop the Scanner\n');
        end
        %dump the final events
        [keycode, secs] = KbQueueDump;%this contains both the pulses and keypresses.
        %log everything but "pulse keys" as pulses, not as keypresses.
        pulses          = (keycode == KbName(p.keys.pulse));
        if any(~pulses);%log keys presses if only there is one
            Log(secs(~pulses), 1000,keycode(~pulses), p.phase, p.block);
        end
        if any(pulses);%log pulses if only there is one
            Log(secs(pulses), 0,keycode(pulses), p.phase, p.block);
        end
        
        %% Save Data  
        save_data(p);
        
        %stop the queue
        KbQueueStop(p.ptb.device);
        KbQueueRelease(p.ptb.device);
        
    end

    function QuadrantLoc(p)        
    end

    function Retinotopy(p)        
    end

    function [TimeFeedbackOffset]=Trial(nTrial,TimeStimOnset, stim_id, RP, block, phase)
        %% Run one trial
        StartEyelinkRecording(nTrial,stim_id,p.var.ExpPhase, stim_id, RP); %I would be cautious here, the first trial is never recorded in the EDF file, reason yet unknown.
        % Save trial info
        TrialStart = GetSecs;
        Eyelink('message', sprintf('ACTIVE_RULE %i', RP));
        Eyelink('message', sprintf('STIM_ID %i', stim_id));
        Log(TrialStart, 1, stim_id, phase, block); 
        Log(TrialStart, 2, RP, phase, block); 
        MarkCED( p.com.lpt.address, 100+RP);
        MarkCED( p.com.lpt.address, 110+stim_id);
        
        %% Fixation Onset
        fix          = [p.ptb.CrossPosition_x p.ptb.CrossPosition_y];
        FixCross     = [fix(1)-1,fix(2)-p.ptb.fc_size,fix(1)+1,fix(2)+p.ptb.fc_size;fix(1)-p.ptb.fc_size,fix(2)-1,fix(1)+p.ptb.fc_size,fix(2)+1];        
        Screen('FillRect', p.ptb.w , p.stim.bg, [] ); %always create a gray background
        Screen('FillRect',  p.ptb.w, [255,255,255], FixCross');%draw the prestimus cross atop
        Screen('DrawingFinished',p.ptb.w,0);        
        TimeCrossOn  = Screen('Flip',p.ptb.w);
        Log(TimeCrossOn, 3, nan, phase, block);
        Eyelink('Message', 'FIXON');
        MarkCED(p.com.lpt.address, 3);
        
        %% Draw the stimulus to the buffer
        Screen('DrawTexture', p.ptb.w, p.ptb.gabortex, [], [], ...
                0+90*stim_id, [], [], [], [], kPsychDontDoRotation, [0, .1, 50, 100, 1, 0, 0, 0]);        
        %draw also the fixation cross
        Screen('FillRect',  p.ptb.w, [255,255,255], FixCross');        
        Screen('DrawingFinished',p.ptb.w,0);
        
        %% STIMULUS ONSET
        TimeStimOnset  = Screen('Flip',p.ptb.w,TimeStimOnset,0);%asap and dont clear
        Log(TimeStimOnset, 4, nan, phase, block); 
        Eyelink('Message', 'StimOnset');
        Eyelink('Message', 'SYNCTIME');
        MarkCED( p.com.lpt.address, 4);        
        
        %% Check for key events
        [keycode, secs] = KbQueueDump;%this contains both the pulses and keypresses.
        if numel(keycode)
            %log pulses            
            pulses = (keycode == KbName(p.keys.pulse));            
            if any(pulses);%log pulses if only there is one
                Log(secs(pulses), 0, keycode(pulses), p.phase, p.block);
            end
        end
        KbQueueFlush(p.ptb.device);
        %% Stimulus Offset        
        Screen('FillRect',  p.ptb.w, [255,255,255], FixCross');                
        TimeStimOffset  = Screen('Flip', p.ptb.w, TimeStimOnset+0.5, 0); %asap and dont clear
        
        Log(TimeStimOffset, 5, nan, phase, block); 
        Eyelink('Message', 'StimOff');
        MarkCED( p.com.lpt.address, 5);        

        %% Now wait for response!
        start = GetSecs;
        response = nan;
        correct = nan;
        RT = nan;
        while (GetSecs-start) < 10
            [keycodes, secs] = KbQueueDump;
            if numel(keycodes)
                for iii = 1:length(keycodes)
                    RT = secs(iii);
                    keys = KbName(keycodes(iii));
                    switch keys
                        case  p.keys.quit
                            throw(MException('EXP:Quit', 'User request quit'));
                        case p.keys.answer_a                        
                            response = 0;
                            break
                        case p.keys.answer_b
                            response = 1;    
                            break
                        case p.keys.pulse
                          Log(RT, 0, NaN, phase, block);
                    end  
                end
                if ~isnan(response)
                    break
                end
            end
        end
        MarkCED(p.com.lpt.address, 70+response);
        Eyelink('message', sprintf('ANSWER %i', response));
        Log(RT, 5, response, phase, block);         
        Log(RT, 6, RT-start, phase, block);
        
        %% Show feedback
        TimeFeedbackOnset = RT + 0.1;
        % Was the answer correct?
        % If rule A then seq.reward_probability(trial) == 0 and:
        %   Rule rewards ANSWER_A and STIM_A and ANSWER_B and STIM_B      
        correct = 0;
        give_reward = 0;
        if RP == 0
            % Rule A is active
            if response == stim_id
                correct = 1;
                give_reward = binornd(1, reward_probabilities(1));
            end
        elseif RP == 1
            % No rule is active / both rules are active
                correct = 1;
                give_reward = binornd(1, reward_probabilities(2));
        else
            % Rule B is active
            if response ~= stim_id
                correct = 1;
                give_reward = binornd(1, 1-reward_probabilities(3));
            end
        end
        fprintf('RESPONSE: %i, RP: %i, %2.2f, GR: %i, C:%i\n', response, RP, reward_probabilities(RP+1), give_reward, correct)        
        Log(RT, 7, correct, phase, block); 
        Eyelink('message', sprintf('CORRECT %i', correct));
        MarkCED( p.com.lpt.address, 120+correct);
        
        Screen('FillRect', p.ptb.w , p.stim.bg, []); 
        if give_reward
            Screen('FillRect',  p.ptb.w, [0,200,0], FixCross');        
        else
           Screen('FillRect',  p.ptb.w, [200,0,0], FixCross');        
        end
        
        TimeFeedback  = Screen('Flip',p.ptb.w,TimeFeedbackOnset,0);        
        
        Eyelink('message', sprintf('FEEDBACK %i', give_reward));
        Log(TimeFeedback, 8, give_reward, phase, block);      
        MarkCED( p.com.lpt.address, 130+give_reward);
        
        %% STIM OFF immediately
        Screen('FillRect', p.ptb.w , p.stim.bg, []); %always create a gray background
        Screen('FillRect',  p.ptb.w, [255,255,255], FixCross');%draw the prestimus cross atop
        TimeFeedbackOffset = Screen('Flip',p.ptb.w,TimeFeedback+0.4, 0);    
        
        Eyelink('message', 'FEEDBACKOFF');        
        Log(TimeFeedbackOffset, 9, 0, phase, block); 
        MarkCED( p.com.lpt.address, 140);

    end

    function SetParams        
        %mrt business
        p.mrt.dummy_scan              = 0; %this will wait until the 6th image is acquired.
        p.mrt.LastScans               = 0; %number of scans after the offset of the last stimulus
        p.mrt.tr                      = 2; %in seconds.
        
        %will count the number of events to be logged
        p.var.event_count             = 0;
        
        
        %% relative path to stim and experiments
        %Path Business.
        [~, hostname]                 = system('hostname');
        p.hostname                    = deblank(hostname);
        
        if strcmp(p.hostname, 'larry.local')
            p.path.baselocation           = '/Users/nwilming/u/immuno/data/';
        elseif strcmp(p.hostname, 'behavioral_lab')
            p.path.baselocation           = 'XXX';
        else
            p.path.baselocation           = 'C:\Users\...\Documents\Experiments\Immuno';
        end
        %create the base folder if not yet there.
        if exist(p.path.baselocation) == 0
            mkdir(p.path.baselocation);
        end
       
        p.subject                       = subject; %subject id
        p.timestamp                     = datestr(now, 30); %the time_stamp of the current experiment.
        
        %% %%%%%%%%%%%%%%%%%%%%%%%%%
        
        p.stim.bg                   = [.5, .5, .5];                
        p.stim.white                = get_color('white');
        %% font size and background gray level
        p.text.fontname                = 'Times New Roman';
        p.text.fontsize                = 18;
        p.text.fixsize                 = 60;
                
        
        %% keys to be used during the experiment:
        %This part is highly specific for your system and recording setup,
        %please enter the correct key identifiers. You can get this information calling the
        %KbName function and replacing the code below for the key below.
        %1, 6 ==> Right
        %2, 7 ==> Left
        %3, 8 ==> Down
        %4, 9 ==> Up (confirm)
        %5    ==> Pulse from the scanner
        
        KbName('UnifyKeyNames');
        p.keys.confirm                 = '4$';%
        p.keys.answer_a                = '1!';
        p.keys.answer_b                = '2@';       
        p.keys.pulse                   = '5%';
        p.keys.el_calib                = 'v';
        p.keys.el_valid                = 'c';
        p.keys.escape                  = 'ESCAPE';
        p.keys.enter                   = 'return';
        p.keys.quit                    = 'q';
        p.keylist = {p.keys.confirm, p.keys.answer_a, p.keys.answer_b, p.keys.pulse,...
            p.keys.el_calib, p.keys.el_valid, p.keys.enter};
        %% %%%%%%%%%%%%%%%%%%%%%%%%%
        %Communication business
        %parallel port
        p.com.lpt.address = 888;%parallel port of the computer.                                                                     
        
        %Record which Phase are we going to run in this run.
        p.stim.phase                   = phase;        
        p.out.log                     = zeros(1000000, 5).*NaN;%Experimental LOG.
        
        %%
        p.var.current_bg              = p.stim.bg;%current background to be used.        
        %save(p.path.path_param,'p');                
    end

    function ShowInstruction(nInstruct,waitforkeypress,varargin)
        %ShowInstruction(nInstruct,waitforkeypress)
        %if waitforkeypress is 1, ==> subject presses a button to proceed
        %if waitforkeypress is 0, ==> text is shown for VARARGIN seconds.
        
        
        [text]= GetText(nInstruct);
        ShowText(text);
        if waitforkeypress %and blank the screen as soon as the key is pressed
            KbStrokeWait(p.ptb.device);
        else
            WaitSecs(varargin{1});
        end
        Screen('FillRect',p.ptb.w,p.var.current_bg);
        t = Screen('Flip',p.ptb.w);
        
        function ShowText(text)            
            Screen('FillRect',p.ptb.w,p.var.current_bg);
            DrawFormattedText(p.ptb.w, text, 'center', 'center', p.stim.white,[],[],[],2,[]);
            t=Screen('Flip',p.ptb.w);
            Log(t,-1,nInstruct, nan, nan);
            %show the messages at the experimenter screen
            fprintf('=========================================================\n');
            fprintf('Text shown to the subject:\n');
            fprintf(text);
            fprintf('=========================================================\n');
            
        end
    end

    function [text]=GetText(nInstruct)
        if nInstruct == 0 %Eyetracking calibration            
            text = ['Wir kalibrieren jetzt den Eye-Tracker.\n\n' ...
                'Bitte fixieren Sie die nun folgenden Kreise und \n' ...
                'schauen Sie so lange darauf, wie sie zu sehen sind.\n\n' ...
                'Nach der Kalibrierung duerfen Sie Ihren Kopf nicht mehr bewegen.\n'...
                'Sollten Sie Ihre Position noch veraendern muessen, tun Sie dies jetzt.\n'...
                'Die beste Position ist meist die bequemste.\n\n'...
                'Bitte druecken Sie jetzt den oberen Knopf, \n' ...
                'um mit der Kalibrierung weiterzumachen.\n' ...
                ];
            
        elseif nInstruct == 1 %Retinotopy.
            text = ['Ihre naechste Aufgabe ist es auf Veraenderungen des\n' ...
                'Fixationskreuzes zu achten. Sollte der linke Arm des Kreuzes\n'...
                'verschwinden druecken sie die Linke Taste! Verschwindet der rechte\n'...
                'Arm druecken Sie die rechte Taste\n'...
                'Druecken Sie einen Knopf um weiter zu machen.'];
            
        elseif nInstruct == 2 %Task.
            text = ['Nun beginnt ein weitere Block des Experimentes.\n'...
                'Finden Sie herraus welche Regel gerade korrekt ist!\n'...
                'Zur Erinnerung:\n Regel A: Links = -, Rechts = |\n'...
                ' Regel B: Rechts = -, Links = |\n'...
                'Druecken Sie einen Knopf um weiter zu machen.'];
            
        elseif nInstruct == 3 %Q Rule A.
            text = ['Im naechsten Block ist Regel A die richtige.\n'...                
                'Zur Erinnerung:\n Regel A: Links = -, Rechts = |\n'...                
                'Druecken Sie einen Knopf um weiter zu machen.'];
            
        elseif nInstruct == 4 %Q Rule B.
            text = ['Im naechsten Block ist Regel B die richtige.\n'...                
                'Zur Erinnerung:\n Regel B: Rechts = -, Links = |\n'...                
                'Druecken Sie einen Knopf um weiter zu machen.'];
        else
            text = {''};
        end
    end

    function SetPTB
        %Sets the parameters related to the PTB toolbox. Including
        %fontsizes, font names.
        %Default parameters
        Screen('Preference', 'SkipSyncTests', 1);
        Screen('Preference', 'DefaultFontSize', p.text.fontsize);
        Screen('Preference', 'DefaultFontName', p.text.fontname);
        Screen('Preference', 'TextAntiAliasing',2);%enable textantialiasing high quality
        Screen('Preference', 'VisualDebuglevel', 0);
        Screen('Preference', 'SkipSyncTests', 1);
        Screen('Preference', 'SuppressAllWarnings', 1);
        %%Find the number of the screen to be opened
        screens                     =  Screen('Screens');
        p.ptb.screenNumber          =  max(screens);%the maximum is the second monitor
        %Make everything transparent for debugging purposes.
        if debug
            commandwindow;
            PsychDebugWindowConfiguration;
        end
        %set the resolution correctly
        res = Screen('resolution',p.ptb.screenNumber);
        HideCursor(p.ptb.screenNumber);%make sure that the mouse is not shown at the participant's monitor
        %spit out the resolution,
        fprintf('Resolution of the screen is %dx%d...\n',res.width,res.height);
        
        %Open a graphics window using PTB
        [p.ptb.w p.ptb.rect]        = Screen('OpenWindow', p.ptb.screenNumber, p.var.current_bg);
        %Screen('BlendFunction', p.ptb.w, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        Screen('Flip',p.ptb.w);%make the bg
        
        p.ptb.slack                 = Screen('GetFlipInterval',p.ptb.w)./2;
        [p.ptb.width, p.ptb.height] = Screen('WindowSize', p.ptb.screenNumber);
        
        %find the mid position on the screen.
        p.ptb.midpoint              = [ p.ptb.width./2 p.ptb.height./2];
        %NOTE about RECT:
        %RectLeft=1, RectTop=2, RectRight=3, RectBottom=4.                
        p.ptb.CrossPosition_x       = p.ptb.midpoint(1);
        p.ptb.CrossPosition_y       = p.ptb.midpoint(2);
        %cross position for the eyetracker screen.                
        p.ptb.fc_size               = 10;
        %
        %%
        %priorityLevel=MaxPriority(['GetSecs'],['KbCheck'],['KbWait'],['GetClicks']);
        Priority(MaxPriority(p.ptb.w));
        %this is necessary for the Eyelink calibration
        %InitializePsychSound(0)
        %sound('Open')
        %         Beeper(1000)
        if IsWindows
            LoadPsychHID;
        end
        %%%%%%%%%%%%%%%%%%%%%%%%%%%Prepare the keypress queue listening.
        p.ptb.device        = -1;
        %get all the required keys in a vector
        p.ptb.keysOfInterest = [];
        for i = fields(p.keys)';
            p.ptb.keysOfInterest = [p.ptb.keysOfInterest KbName(p.keys.(i{1}))];
        end
        p.ptb.keysOfInterest
        % fprintf('Key listening will be restricted to %d\n', p.keys.keylist)
        %p.keys.keylist
        %
        %p.ptb.keysOfInterest=zeros(1,256);
        %p.ptb.keysOfInterest(p.keys.confirm) = 1;
        %p.ptb.keysOfInterest = zeros(1, 256);       
        %p.ptb.keysOfInterest(KbName(p.keylist)) = 1; % only listen to those keys!
        RestrictKeysForKbCheck(p.ptb.keysOfInterest);
        % first four are the buttons in mode 001, escape and space are for
        % the experimenter, rest is for esting
        %[idx, names, all] = GetKeyboardIndices();        
        %for kbqdev = idx
        %    PsychHID('KbQueueCreate', kbqdev,  p.ptb.keysOfInterest);
        %    PsychHID('KbQueueStart', kbqdev);
        %    WaitSecs(.1);
        %    PsychHID('KbQueueFlush', kbqdev);
        %end
        %create a queue sensitive to only relevant keys.
        %p.ptb.device = idx;
        KbQueueCreate(p.ptb.device);%, p.ptb.keysOfInterest);%default device.
        %%%%%%%%%%%%%%%%%%%%%%%%%%%
        %prepare parallel port communication. This relies on cogent i
        %think. We could do it with PTB as well.
        if IsWindows
            config_io;
            outp(p.com.lpt.address,0);
            if( cogent.io.status ~= 0 )
                error('inp/outp installation failed');
            end
        end
        
        %% Build a procedural gabor texture for a gabor with a support of tw x th
        % pixels, and a RGB color offset of 0.5 -- a 50% gray.        
        p.ptb.gabortex = CreateProceduralGabor(p.ptb.w, p.ptb.width, p.ptb.height, 0, [0.5 0.5 0.5 0.0]);

        
        %% %%%%%%%%%%%%%%%%%%%%%%%%%
        %Make final reminders to the experimenter to avoid false starts,
        %which are annoying. Here I specifically send test pulses to the
        %physio computer and check if everything OK.
        k = 0;
%         while ~(k == p.keys.el_calib);%press V to continue
%             pause(0.1);
%             outp(p.com.lpt.address,244);%244 means all but the UCS channel (so that we dont shock the subject during initialization).
%             fprintf('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n');
%             fprintf('1/ Red cable has to be connected to the Cogent BOX\n');
%             fprintf('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n');
%             fprintf('2/ D2 Connection not to forget on the LPT panel\n');
%             fprintf('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n');
%             fprintf('3/ Switch the SCR cable\n');
%             fprintf('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n');
%             fprintf('4/ Button box has to be on\n');
%             fprintf('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n');
%             fprintf('5/ Did the trigger test work?\n!!!!!!You MUST observe 5 pulses on the PHYSIOCOMPUTER!!!!!\n\n\nPress V(alidate) to continue experiment or C to continue sending test pulses...\n')
%             [~, k] = KbStrokeWait(p.ptb.device);
%             k = find(k);
%         end
        fprintf('Continuing...\n');
        
        

    end

    function [t]=StartEyelinkRecording(nTrial, phase, rp, stim, block_id)
        if ~NoEyelink
            t = [];            
            Eyelink('Message', 'TRIALID: %04d, PHASE: %04d, RP: %04d, STIM: %04d, BLOCK %04d', nTrial, phase, rp, stim, block_id);                        
            Eyelink('Command', 'record_status_message "Stim: %02d, rp: %d"', stim, rp);             
            t = GetSecs;
            Log(t, 199, NaN, nan, nan);
        else
            t = GetSecs;
        end
    end

    function MarkCED(socket,port)
        %send pulse to SCR#
        outp(socket,port);
        WaitSecs(0.01);
        outp(socket,0);
    end

    function p=InitEyeLink(p)
        %
        if EyelinkInit(NoEyelink)%use 0 to init normaly
            fprintf('=================\nEyelink initialized correctly...\n')
        else
            fprintf('=================\nThere is problem in Eyelink initialization\n')
            keyboard;
        end
        %
        WaitSecs(0.5);
        [~, vs] = Eyelink('GetTrackerVersion');
        fprintf('=================\nRunning experiment on a ''%s'' tracker.\n', vs );

        %
        el                          = EyelinkInitDefaults(p.ptb.w);
        %update the defaults of the eyelink tracker
        el.backgroundcolour         = p.stim.bg;
        el.msgfontcolour            = WhiteIndex(el.window);
        el.imgtitlecolour           = WhiteIndex(el.window);
        el.targetbeep               = 0;
        el.calibrationtargetcolour  = WhiteIndex(el.window);
        el.calibrationtargetsize    = 1.5;
        el.calibrationtargetwidth   = 0.5;
        el.displayCalResults        = 1;
        el.eyeimgsize               = 50;
        el.waitformodereadytime     = 25;%ms
        el.msgfont                  = 'Times New Roman';
        el.cal_target_beep          =  [0 0 0];%[1250 0.6 0.05];
        %shut all sounds off
        el.drift_correction_target_beep = [0 0 0];
        el.calibration_failed_beep      = [0 0 0];
        el.calibration_success_beep     = [0 0 0];
        el.drift_correction_failed_beep = [0 0 0];
        el.drift_correction_success_beep= [0 0 0];
        EyelinkUpdateDefaults(el);
        PsychEyelinkDispatchCallback(el);

        % open file.
        p.edffile = sprintf('%d%d%d.edf', p.subject, p.phase, p.block)
        res = Eyelink('Openfile', p.edffile);
        %
        %Eyelink('command', 'add_file_preamble_text ''Recorded by EyelinkToolbox FearAmy Experiment (Selim Onat)''');
        Eyelink('command', 'screen_pixel_coords = %ld %ld %ld %ld', 0, 0, p.ptb.width-1, p.ptb.height-1);
        Eyelink('message', 'DISPLAY_COORDS %ld %ld %ld %ld', 0, 0, p.ptb.width-1, p.ptb.height-1);
        % set calibration type.
        Eyelink('command','auto_calibration_messages = YES');
        Eyelink('command', 'calibration_type = HV13');
        Eyelink('command', 'select_parser_configuration = 1');
        %what do we want to record
        Eyelink('command', 'file_sample_data  = LEFT,RIGHT,GAZE,HREF,AREA,GAZERES,STATUS,INPUT,HTARGET');
        Eyelink('command', 'file_event_filter = LEFT,RIGHT,FIXATION,SACCADE,BLINK,MESSAGE,BUTTON,INPUT');
        Eyelink('command', 'use_ellipse_fitter = no');
        % set sample rate in camera setup screen
        Eyelink('command', 'sample_rate = %d',1000);

    end

    function StopEyelink(filename, path_edf)
        if ~NoEyelink
            try
                fprintf('Trying to stop the Eyelink system with StopEyelink\n');
                Eyelink('StopRecording');
                Log(t, 198, NaN, nan, nan);
                WaitSecs(0.5);
                Eyelink('Closefile');
                display('receiving the EDF file...');
                Eyelink('ReceiveFile', filename, path_edf);
                display('...finished!')
                % Shutdown Eyelink:
                Eyelink('Shutdown');
            catch
                display('StopEyeLink routine didn''t really run well');
            end
        end
    end

    function cleanup
        % Close window:
        sca;
        %set back the old resolution
        if strcmp(p.hostname,'triostim1')
            %            Screen('Resolution',p.ptb.screenNumber, p.ptb.oldres.width, p.ptb.oldres.height );
            %show the cursor
            ShowCursor(p.ptb.screenNumber);
        end
        %
        commandwindow;
        KbQueueStop(p.ptb.device);
        KbQueueRelease(p.ptb.device);
    end

    function CalibrateEL        
        fprintf('=================\n=================\nEntering Eyelink Calibration\n')
        p.var.ExpPhase  = 0;            
        EyelinkDoTrackerSetup(el);
        %Returns 'messageString' text associated with result of last calibration
        [~, messageString] = Eyelink('CalMessage');
        Eyelink('Message','%s', messageString);%
        WaitSecs(0.05);
        fprintf('=================\n=================\nNow we are done with the calibration\n')

    end

    function Log(ptb_time, event_type, event_info, phase, block)
        %Phases:        
        % 1 - training day one
        % 2 - fMRI day one
        % 3 - training day two
        % 4 - fMRI day two
        % 5 - training day three
        % 6 - fMRI day three
        
        % Blocks:
        % 0 - Instruction 
        % 1 - Retinotopic mapping
        % 2 - Experiment
        % 3 - Quadrant mapping       
                     
        %event types are as follows:
        %
        % Pulse Detection      :     0    info: NaN;
        % Stimulus ID          :     1    info: stim_id         Log(TrialStart, 1, stim_id); 
        % Reward Probability   :     2    info: RP              Log(TrialStart, 2, RP); 
        % Fix Cross On         :     3    info: nan             Log(TimeCrossOn, 3, nan)
        % Stimulus On          :     4    info: nan             Log(TimeStimOnset, 4, nan);             
        % Stimulus Off         :     5    info: nan             Log(TimeStimOffset, 5, nan);               
        % Response             :     6    info: response        Log(RT, 5, response); 
        % Response time        :     7    info: respones time   Log(RT, 6, RT-start); 
        % Stim correct         :     8    info: correct         Log(RT, 7, correct); 
        % Feedback             :     9    info: give_reward     Log(TimeFeedback, 8, give_reward);       
        % Trial end            :    10    info: nan             Log(TimeFeedbackOffset, 9, 0);    
        
        for iii = 1:length(ptb_time)
            p.var.event_count                = p.var.event_count + 1;            
            p.out.log(p.var.event_count,:)   = [ptb_time(iii) event_type event_info(iii) phase block];
            %fprintf('LOG: %2.2f, %i, %i, %i, %i \n', p.out.log(p.var.event_count, :))
        end        
        
    end

    function [secs]=WaitPulse(keycode,n)
        %[secs]=WaitPulse(keycode,n)
        %
        %   This function waits for the Nth upcoming pulse. If N=1, it will wait for
        %   the very next pulse to arrive. 1 MEANS NEXT PULSE. So if you wish to wait
        %   for 6 full dummy scans, you should use N = 7 to be sure that at least 6
        %   full acquisitions are finished.
        %
        %   The function avoids KbCheck, KbWait functions, but relies on the OS
        %   level event queues, which are much less likely to skip short events. A
        %   nice discussion on the topic can be found here:
        %   http://ftp.tuebingen.mpg.de/pub/pub_dahl/stmdev10_D/Matlab6/Toolboxes/Psychtoolbox/PsychDocumentation/KbQueue.html
        
        %KbQueueFlush;KbQueueStop;KbQueueRelease;WaitSecs(1);
        fprintf('Will wait for %i dummy pulses...\n',n);
        if n ~= 0
            secs  = nan(1,n);
            pulse = 0;
            dummy = [];
            while pulse < n
                dummy         = KbTriggerWait(keycode,p.ptb.device);
                pulse         = pulse + 1;
                secs(pulse+1) = dummy;
                Log(dummy,0,NaN);
            end
        else
            secs = GetSecs;
        end
    end

    function [keycode, secs] = KbQueueDump
        %[keycode, secs] = KbQueueDump
        %   Will dump all the events accumulated in the queue.        
        keycode = [];
        secs    = [];
        pressed = [];        
        while KbEventAvail(p.ptb.device)
            [evt, n]   = KbEventGet(p.ptb.device);
            n          = n + 1;
            keycode(n) = evt.Keycode;
            pressed(n) = evt.Pressed;
            secs(n)    = evt.Time;            
        end
        i           = pressed == 1;
        keycode(~i) = [];
        secs(~i)    = [];
        
    end
    
    function [keyIsDown firstPress] = check_kbqueues(devices)
        firstPress = boolean(zeros(1, 256)); 
        keyIsDown = false;
        for device = devices
            [kD, fP] = PsychHID('KbQueueCheck', device);
            keyIsDown = keyIsDown | kD;
            firstPress = firstPress | boolean(fP);
        end
    end

    function save_data(p)
        path = fullfile(p.path.baselocation, p.subject, sprintf('%d_%d', p.phase, p.block)); %subject folder, first we save it to the temp folder.        
        path_edf = fullfile(path, sprintf('%d_%d_%d.edf', p.subject, p.phase, p.block));
        path_data = fullfile(path, sprintf('%d_%d_%d_data.mat', p.subject, p.phase, p.block));
        
        %get the eyelink file back to this computer
        StopEyelink(p.edffile, path_edf);
        %trim the log file and save
        p.out.log(p.var.event_count, :)
        p.out.log = p.out.log(1:p.var.event_count,:);
        %shift the time so that the first timestamp is equal to zero
        p.out.log(:,1) = p.out.log(:,1) - p.out.log(1);
        p.out.log      = p.out.log;%copy it to the output variable.
        save(path_data, 'p');        
        % Reset Log 
        p.out.log      = zeros(1000000, 5).*NaN;%Experimental LOG.
    end



end