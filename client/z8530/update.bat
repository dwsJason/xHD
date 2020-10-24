merlin32 -v link.s
cd ..\..
cadius deletefile test1.po /TEST1/xHD.gsos
cadius addfile test1.po /TEST1 client/z8530/xHD.gsos
cd client/z8530

cadius deletefile cfa1.po /CFA1/System/Drivers/xHD.gsos
cadius addfile cfa1.po /CFA1/System/Drivers ./xHD.gsos



