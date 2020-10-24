git clone https://github.com/ricky-davis/AstroLauncher.git
curl.exe -LO https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe
$proc = Start-Process -FilePath ".\Miniconda3-latest-Windows-x86_64.exe" -ArgumentList "/S /InstallationType=AllUsers /AddToPath=1 /RegisterPython=1 /D=C:\Miniconda3" -PassThru
$proc | Wait-Process
iex "& 'C:\Miniconda3\shell\condabin\conda-hook.ps1' ; conda activate 'C:\Miniconda3' "
conda install psutil
cd .\AstroLauncher\
pip install -r .\requirements.txt
pip install python-certifi-win32
#python AstroLauncher.py --path "C:\Astroneer\astroneer"
