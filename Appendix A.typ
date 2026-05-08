 = Carla and Pycharm IDE Interfacing
To control and communicate with Carla, the Python API is used. Therefore, it is necessary to have a Python version compatible with the Carla version we plan to use. However, updates to Carla often require updating the Python version at regular intervals. This makes it mandatory to reconcile Carla and Python with each new update. However, by taking advantage of uv’s ability to use different Python versions through different digital environments, we can solve this problem. Thus, we can have multiple environments and Carla models on the same computer, which also reduces the burden of this process. The steps for setting up Carla-uv communication are as follows:
 #list(
 [Downloaded Carla 0.9.16(UE4)],
 
 [Installed Pycharm IDE],

 [Installed uv python package and project manager:
#raw("set PROJECT=carla_lane
powershell -ExecutionPolicy ByPass -c \"irm https://astral.sh/uv/0.10.8/install.ps1 | iex\"
uv clean
git clone https://github.com/axmud/lane_assist.git %PROJECT%
uv init %PROJECT% -p \"==3.10.20\"
cd %PROJECT%
uv add setuptools==66.1.1
uv add wheel==0.46.3
uv add albumentations==0.4.6 --no-build-isolation
uv add --requirements requirements.txt", lang: "cmd", block: true)],
[Pytorch requirements. We need to add these lines to the end of pyproject.toml file in the project folder:
#raw("cu121 = [\"torch==2.3.1\", \"torchvision==0.18.1\", \"torchaudio==2.3.1\"]
[tool.uv.sources]
torch = [
  { index = \"pytorch-cu121\", extra = \"cu121\" }
]
torchvision = [
  { index = \"pytorch-cu121\", extra = \"cu121\" }
]
torchaudio = [
  { index = \"pytorch-cu121\", extra = \"cu121\" }
]
[[tool.uv.index]]
name = \"pytorch-cu121\"
url = \"https://download.pytorch.org/whl/cu121\"
explicit = true", lang: "toml", block: true)],
[Next, we will run this:
#raw("uv sync --extra cu121", lang: "cmd", block: true)],
[Depencency adjustments:
#raw("uv pip install --no-build-isolation -e .
uv pip install numpy==1.23.1
uv pip install hydra-core
uv pip uninstall setuptools
uv pip install setuptools==66.1.1
uv pip install carla==0.9.16", lang: "cmd", block: true)]
)