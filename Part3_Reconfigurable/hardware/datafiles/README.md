#### For testing Weight Stationary mode

The format is the same from part 1. You can use 

* weight_k1.txt, weight_k2.txt ....... weight_k9.txt.  
* activation.txt
* out.txt
* acc_scan.txt: This is a static file that should be kept the same even if you are chainging the other files. The test bench uses this to accumulate partial sums to calculate outputs


#### For testing Output Stationary mode

These files can be generate with the help of the jupyter notebook provided in software directory under this part. All you need is the saved checkpoint of your model

* weight_os.txt
* activation_os.txt
* output_os.txt