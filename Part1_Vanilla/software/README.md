# VGG 16 4 bit quantization

To get weight, activation, and expected output files please use cpu only version of PyTorch to prevent rounding errors that create incorrect outputs.

Additionally, to get our trained model loaded go to:

[4bit Activation >90%](https://drive.google.com/file/d/1nl0Q7PixA0p5ObYYcjTe8l8sOuuUKrn6/view?usp=drive_link)

To download the model, and place it in `Part1_Vanilla/software/result/`

The PSUM error is shown in `psum_error.ipynb` and its pdf equivalent

# Testing the code

Inside `/hardware/sim` run:

`iveri filelist`

or

`iverilog <filelist-contents>`

to create an executable, which can then be run. It should then output test cases passed/failed.