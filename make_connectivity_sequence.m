
function stimuli = make_connectivity_sequence(ns, trials, duration)
stimuli = {};

% Course of experiment:
% 1. Training, exp only
% 2. fMRI, E Q E Q E Q E Q E
% 3. Training, exp only
% 4. fMRI, E Q E Q E Q E Q E
% 5. Training, exp only
% 6. fMRI, E Q E Q E Q E Q E

for s = 1:ns
    stimuli{s} = {};
    for p = 1:6 % This iterates over days.
        if mod(p, 2) == 1   % Training session
            block_types = {'E', 'E', 'E', 'E', 'E', 'E', 'E'};
        else
            block_types = {'E', 'QA', 'E', 'QB', 'E', 'QA', 'E', 'QB', 'E'};
        end
        blocks = {};
        for block = 1:length(block_types)
            type = block_types(block);
            if strcmp(type, 'E')
               [seq, es] = make_exp_sequence(trials);
            else
                %seq = make_Q_sequence(trials, type);
            end
            blocks{block} = seq; %#ok<AGROW>
            
        end
        stimuli{s}{p} = blocks; %#ok<AGROW>
    end
end

    function [seq, es] = make_exp_sequence(trials)
        %% Makes a sequence of rules that change with a specific hazard rate.
        validities = [0, 0.25, 0.75, 1];
        block_length = 5;
        seq.type = 'CV';
        seq.stim = randi(2, 1, trials)-1;
        es = [];
        seq.validity = repmat(randsample(validities, 1), 1, block_length);
        seq.onset = [1, zeros(1, block_length-1)];
        seq.rewarded_rule = binornd(1, seq.validity(end), 1, block_length);
        while length(seq.validity)<trials
            vs = randsample(setdiff(validities, seq.validity(end)), 1);
            seq.validity = [seq.validity, repmat(vs, 1, block_length)];
            seq.onset = [seq.onset, 1, zeros(1, block_length-1)];
            rewarded_rule = binornd(1, vs, 1, block_length);
            seq.rewarded_rule = [seq.rewarded_rule, rewarded_rule];
        end
        seq.validity = seq.validity(1:trials);
        seq.isi = duration(1) + (duration(2)-duration(1)).*rand(1, trials);
        seq.jitter = 0.3 + 0.7*rand(1, trials);
        seq.isi = seq.isi-seq.jitter;
    end

end