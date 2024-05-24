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

handler = colorlog.StreamHandler()
handler.setFormatter(colorlog.ColoredFormatter('%(log_color)s[%(asctime)s] - OpenTAKServer[%(process)d] - %(module)s - %(levelname)s - %(message)s', datefmt="%Y-%m-%d %H:%M:%S"))
logger = colorlog.getLogger('ots_upgrade')
logger.addHandler(handler)

logger.warning("This script will make modifications to your database. Please make a backup of your database before proceeding in case something goes wrong.")
while True:
    proceed = input(colorama.Fore.YELLOW + "Would you like to continue? [y/N]")
    if proceed.lower().startswith('y'):
        break
    else:
        sys.exit()

opentakserver_version = opentakserver.__version_tuple__
major = opentakserver_version[0]
minor = opentakserver_version[1]
patch = opentakserver_version[2]

ots_directory = os.path.dirname(os.path.realpath(opentakserver.__file__))
logger.info("Found OpenTAKServer at {}".format(ots_directory))

logger.info("Found OpenTAKServer version {}.{}.{}".format(major, minor, patch))
logger.info("Upgrading OpenTAKServer...")
pip.main(["install", "opentakserver", "-U"])
importlib.reload(opentakserver)

# Flask-Migrate won't be installed yet if the old version of OpenTAKServer is <= 1.1.10 so import it here after upgrading
# OpenTAKServer to the latest version
import flask_migrate

if major == 1 and minor <= 1 and patch <= 10:
    logger.info("Old version of OpenTAKServer was {}.{}.{}, stamping DB version as 4c7909c34d4e".format(major, minor, patch))
    with app.app_context():
        flask_migrate.stamp(directory=os.path.join(ots_directory, "migrations"), revision="4c7909c34d4e")

logger.info("Upgrading DB Schema...")
with app.app_context():
    try:
        flask_migrate.upgrade(directory=os.path.join(ots_directory, "migrations"))
        logger.info("Upgrade completed successfully")
    except BaseException as e:
        logger.error("Database migration failed: {}".format(e))
        logger.error(traceback.format_exc())
