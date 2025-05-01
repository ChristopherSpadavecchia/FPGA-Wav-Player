# FPGA-Wav-Player
FPGA Wav Player by Christopher Spadavecchia &amp; Eli Shtindler

This is our final project for CPE 487 taught by Professor Bernard Yett, shoutout to him. 

The goal of our project is to be able to play a .wav file on the Nexys A7 FPGA.

To be able to achieve this goal, we had to download the .wav file to a Micro SD, read the file from the Micro SD, and play back the data from the file.
## 1. Figuring out the .wav (Wave) format using Python
To be able to read the Wave file format, we have to figure out how the song is formatted. To do this, we employed Python to extract and print out information from the .wavfile.

All the information that we used for the Wave file format, we found on this webiste: [WAVE PCM soundfile format](http://soundfile.sapp.org/doc/WaveFormat/).

The WAVE format is a part of Microsoft’s RIFF(Resource Interchange File Format) standard for multimedia file storage.

A RIFF file starts out with a file header followed by a sequence of data chunks. A WAVE file is often just a RIFF file with a single "WAVE" chunk which consists of two sub-chunks: a "fmt "chunk which describes the sound data's format and a "data" chunk containing the actual song data that we want to read.

From the "fmt" chunk we had to extract and print certain components to figure out the format of the song data. The componets that we used and there settings for our test song, "Again by Fetty Wap" are list below.

**NumChannels** which would determine if it was 1 = Mono or 2 = Stereo. -> Project Settings: 2 = Stereo

**SampleRate** which would determine how fast samples are taken -> Project Settings: 48,000 Hz

**BitsPerSample** which would determine how many bits are in sample usually its 8 or 16 bits -> Project Settings: 16 bits

**ByteRate** which is equal to SampleRate * NumChannels * BitsPerSample/8 -> Project Settings: 48000 * 2 * 16/8 = 192,000 bytes per second

From the "data" chunk we had to extract and print certain components to see when the data started, so we could start reading the data.

**Subchunk2ID** which contains the letters "data"(0x64617461 in big-endian form)

**Subchunk2Size** which is equal to NumSamples * NumChannels * BitsPerSample/8 and is equal to the number of bytes in the data </br> -> Project Settings: 1,400,000 samples * 2 * 16/8 = 5,600,000 bytes

We looped through the data until we found the Subchunk2ID which indicated to us that the data started here and we could start reading the data.

## 2. Reading the File from the Micro SD card

Since the FPGA cannot store the .wav file, we had to employ a Micro SD card to be our storage.

To be able to read the Micro SD card, we looked for source code to base our code off and came across this project: 
[Micro SD Reader](https://github.com/douggilliland/MultiComp/blob/master/MultiComp%20(VHDL%20Template)/Components/SDCARD/sd_controller_High_Speed.vhd).


