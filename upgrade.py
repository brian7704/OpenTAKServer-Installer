import importlib
import sys
import traceback

import opentakserver
from opentakserver.app import app
import colorlog
import os
import pip
import platform
import colorama

if platform.system().lower() == 'windows':
    colorama.just_fix_windows_console()
else:
    colorama.init()

handler = colorlog.StreamHandler()
handler.setFormatter(colorlog.ColoredFormatter('%(log_color)s[%(asctime)s] - OpenTAKServer[%(process)d] - %(module)s - %(levelname)s - %(message)s', datefmt="%Y-%m-%d %H:%M:%S"))
logger = colorlog.getLogger('ots_upgrade')
logger.addHandler(handler)

opentakserver_version = opentakserver.__version_tuple__
major = opentakserver_version[0]
minor = opentakserver_version[1]
patch = opentakserver_version[2]

ots_directory = os.path.dirname(os.path.realpath(opentakserver.__file__))
logger.info(f"Found OpenTAKServer version {major}.{minor}.{patch} at {ots_directory}")

logger.warning("This script will make modifications to your database. Please make a backup of your database before proceeding in case something goes wrong.")
while True:
    proceed = input(colorama.Fore.YELLOW + "Would you like to continue? [y/N]" + colorama.Style.RESET_ALL)
    if proceed.lower().startswith('y'):
        break
    else:
        sys.exit()

if platform.system().lower() == 'windows':
    logger.info("Installing unishox2-py3...")
    pip.main(["install", "https://github.com/brian7704/OpenTAKServer-Installer/raw/master/unishox2_py3-1.0.0-cp312-cp312-win_amd64.whl"])


logger.info("Upgrading OpenTAKServer...")
# TODO: Change this once the new version is on PyPI
pip.main(["install", "git+https://github.com/brian7704/OpenTAKServer", "-U"])
importlib.reload(opentakserver)

# Flask-Migrate won't be installed yet if the old version of OpenTAKServer is <= 1.1.10 so import it here after upgrading
# OpenTAKServer to the latest version
import flask_migrate
from flask_migrate import Migrate, stamp
from opentakserver.extensions import db

Migrate(app, db)
logger.disabled = False
logger.parent.handlers.pop()

if major == 1 and minor <= 1 and patch <= 10:
    logger.info("Old version of OpenTAKServer was {}.{}.{}, stamping DB version as 4c7909c34d4e".format(major, minor, patch))
    with app.app_context():
        stamp(directory=os.path.join(ots_directory, "migrations"), revision="4c7909c34d4e")

logger.info("Upgrading DB Schema...")
with app.app_context():
    try:
        flask_migrate.upgrade(directory=os.path.join(ots_directory, "migrations"))
        logger.info("Upgrade completed successfully")
    except BaseException as e:
        logger.error("Database migration failed: {}".format(e))
        logger.error(traceback.format_exc())

logger.info("The upgrade is complete. Please restart OpenTAKServer if it is running.")
