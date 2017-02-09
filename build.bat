pushd %~dp0

dub build -b release
copy /Y movephoto.exe c:\cloud\soft\cmdline\movephoto.exe
copy /Y FreeImage.dll c:\cloud\soft\cmdline\FreeImage.dll

popd