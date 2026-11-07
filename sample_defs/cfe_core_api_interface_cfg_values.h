/************************************************************************
 * NASA Docket No. GSC-19,200-1, and identified as "cFS Draco"
 *
 * Copyright (c) 2023 United States Government as represented by the
 * Administrator of the National Aeronautics and Space Administration.
 * All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may
 * not use this file except in compliance with the License. You may obtain
 * a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 ************************************************************************/

/**
 * @file
 *
 * Purpose:
 *   This header file contains the mission configuration parameters and
 *   typedefs with mission scope.
 */

#ifndef DEFAULT_CFE_CORE_API_INTERFACE_CFG_VALUES_H
#define DEFAULT_CFE_CORE_API_INTERFACE_CFG_VALUES_H

/* Use the default configuration value for all */
#define CFE_MISSION_CORE_API_CFGVAL(x) DEFAULT_CFE_MISSION_CORE_API_##x

#endif /* DEFAULT_CFE_CORE_API_INTERFACE_CFG_VALUES_H */

/* MISSION MODULE LIMITS BEGIN */
#define MODULE_LIMIT_BASE_CFGVAL(x) DEFAULT_CFE_MISSION_CORE_API_##x
#undef CFE_MISSION_CORE_API_CFGVAL
#define CFE_MISSION_CORE_API_CFGVAL(x) MODULE_LIMIT_##x
#define MODULE_LIMIT_MAX_API_LEN ((MODULE_LIMIT_BASE_CFGVAL(MAX_API_LEN) > 24) ? MODULE_LIMIT_BASE_CFGVAL(MAX_API_LEN) : 24)
#define MODULE_LIMIT_MAX_FILE_LEN ((MODULE_LIMIT_BASE_CFGVAL(MAX_FILE_LEN) > 24) ? MODULE_LIMIT_BASE_CFGVAL(MAX_FILE_LEN) : 24)
#define MODULE_LIMIT_MAX_NUM_FILES MODULE_LIMIT_BASE_CFGVAL(MAX_NUM_FILES)
#define MODULE_LIMIT_MAX_PATH_LEN MODULE_LIMIT_BASE_CFGVAL(MAX_PATH_LEN)
/* MISSION MODULE LIMITS END */
