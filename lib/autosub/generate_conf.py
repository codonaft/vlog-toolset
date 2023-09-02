#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import glob
import os
import sys
import whisper


def extract_transcripts(filename, model):
    args = {'verbose': True, 'task': 'transcribe', 'language': None}
    result = model.transcribe(filename, **args)
    return [((i['start'], i['end']), i['text']) for i in result['segments']]


def filename_to_clip(filename):
    basename = os.path.basename(filename)
    return int(basename.split('_')[0])


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: %s project_dir/' % sys.argv[0])
        sys.exit(1)

    project_dir = sys.argv[1]
    output = project_dir + '/render.conf'

    #concurrency = 32
    #pool = multiprocessing.Pool(concurrency)

    video_filenames = glob.glob(project_dir + '/0*.mp4')
    video_filenames.sort()

    model = whisper.load_model('base')

    new_config = not os.path.isfile(output)
    if new_config:
        f = open(output, 'w')
        line = '\t'.join(['#filename', 'speed', 'start', 'end', 'text']) + '\n'
        f.write(line)
    else:
        f = open(output, 'r+')
        last_line = f.readlines()[-1]
        first_column = last_line.split('\t')[0]
        last_recorded_filename = first_column.split('#')[-1].strip()
        last_recorded_clip = filename_to_clip(last_recorded_filename)
        skip_lines = len([i for i in video_filenames if filename_to_clip(i) <= last_recorded_clip])
        video_filenames = video_filenames[skip_lines:]

    n = len(video_filenames)

    for i, filename in enumerate(video_filenames):
        num = i + 1
        progress = (num / len(video_filenames)) * 100.0
        print('processing (%d/%d) (%.1f%%) %s' % (num, n, progress, filename))
        try:
            for (start, end), text in extract_transcripts(filename, model):
                line = '\t'.join([os.path.basename(filename), '1.0', str(start), str(end), text]) + '\n'
                f.write(line)
        except Exception as e:
            print('failed to process ' + filename)
            print(e)

    f.close()

    #print('terminating the pool')
    #pool.terminate()
    #pool.join()

    print('done')
    print(output)
