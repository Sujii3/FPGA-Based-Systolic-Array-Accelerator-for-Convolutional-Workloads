## Generating testing files

This part uses the same 4 bit quantized model from part 4. Here is a link to the saved model weights: https://drive.google.com/drive/folders/1oYik9hDFQiUYzald5PRxIHF6hcZWF9iV?usp=drive_link. These weights are loaded and used to generate the ouptput files specifically for weight stationary testing. Files from part 1 are re used for output stationary testing

* Please load your custom model to generate weight_os.txt, activation_os.txt, and output_os.txt. This will be the easiest way to generate you custom testing files. 

* Please place the saved model checkpoint in result/VGG16_quant

* Once generated, these files have to be placed under the `Part3_Reconfigurable/hardware/datafiles` directory

* Please look at the README in `Part3_Reconfigurable/hardware/sim` to understand how to evaluate using these datafiles