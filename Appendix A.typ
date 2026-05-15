= Carla and Pycharm IDE Interfacing
To control and communicate with Carla, the Python API is used. Therefore, it is necessary to have a Python version compatible with the Carla version we plan to use. However, updates to Carla often require updating the Python version at regular intervals. This makes it mandatory to reconcile Carla and Python with each new update. However, by taking advantage of uv’s ability to use different Python versions through different digital environments, we can solve this problem. Thus, we can have multiple environments and Carla models on the same computer, which also reduces the burden of this process. The steps for setting up Carla-uv communication are as follows:
#list(
    [Downloaded Carla 0.9.16(UE4)],

    [Installed Pycharm IDE],

    [Installed uv python package and project manager:
        #raw(
            "set PROJECT=LaneDetCarla
powershell -ExecutionPolicy ByPass -c \"irm https://astral.sh/uv/0.10.8/install.ps1 | iex\"
git clone https://github.com/axmud/LaneDetCarla.git %PROJECT%
cd %PROJECT%
uv venv
.venv\Scripts\activate
uv pip install setuptools==66.1.1
uv pip install wheel==0.46.3
uv pip install albumentations==0.4.6 --no-build-isolation
uv sync --extra cu121
uv pip install --no-build-isolation -e .
uv pip install numpy==1.23.1
uv pip install hydra-core==1.3.2
uv pip install control==0.10.2",
            lang: "cmd",
            block: true,
        )],
)
