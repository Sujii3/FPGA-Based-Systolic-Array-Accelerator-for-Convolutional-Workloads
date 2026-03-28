# Part2_SIMD software folder

To get weight, activation, and expected output files please use cpu only version of PyTorch to prevent rounding errors that create incorrect outputs.

Additionally, to get our trained model loaded go to:

[2bit Activation >90%](https://drive.google.com/file/d/1AFsIBO4dC6t-hkLGNMKFh9DvY_bfjYn6/view?usp=sharing)

To download the model, and place it in `/software/misc/result/`.

Run the `VGG16_Quantization_Aware_Training` to get the activation, output, and correct weight loading scheme.

The format of the weight loading scheme is as follows, and can only have 8 different columns due to only 8 output channels.

```
#col0row15[msb-lsb],col0row13[msb-lst],....,col0row1[msb-lst]#
#col0row14[msb-lsb],col0row12[msb-lst],....,col0row0[msb-lst]#
....
#col7row15[msb-lsb],col0row13[msb-lst],....,col0row1[msb-lst]#
#col7row14[msb-lsb],col0row12[msb-lst],....,col0row0[msb-lst]#
```

The current setup does the first 8 output channels, but `Part5_Alpha/Alpha3_Tiling` does them all.

The PSUM error is shown in `psum_error.ipynb` and its pdf equivalent.