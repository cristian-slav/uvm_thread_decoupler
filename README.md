# uvm_thread_decoupler
Utility class to decouple a task from its caller process so that a call to kill() method of the parent process does not terminate the targeted task.

For details on this project please read the associated article: http://cfs-vision.com/how-to-decouple-threads-in-systemverilog

<h1>Integration Steps</h1>
These are the steps required to decouple a task called __encrypt()__ from its caller process. 
<br/>The term **target task** refers to the task we want to decouple, which is in this case __encrypt()__ task.
<h2>Step #1: Import uvm_thread_decoupler.sv File</h2>
Copy the file [uvm_thread_decoupler.sv](https://github.com/cristian-slav/uvm_thread_decoupler/blob/main/sv/uvm_thread_decoupler.sv) from GitHub into your project and include it in the necessary package:
<br/>
```shell
source Setup.bsh
```
