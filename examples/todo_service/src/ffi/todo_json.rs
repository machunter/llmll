// FFI Stubs for 'todo_json'. Generated ONCE.
// Edit this file to implement the stubs using the crate API.
#![allow(unused_variables, dead_code)]
use crate::LlmllVal;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
pub struct TaskData {
    pub id: String,
    pub title: String,
    pub completed: bool,
    pub priority: i64,
    pub created: String,
    pub completed_date: String,
}

#[derive(Serialize, Deserialize)]
pub struct TaskInputData {
    pub title: String,
    pub priority: i64,
    #[serde(default)]
    pub completed: bool,
}

pub fn parse_tasks(arg0: LlmllVal) -> LlmllVal {
    let json_str = arg0.as_str();
    match serde_json::from_str::<Vec<TaskData>>(json_str) {
        Ok(tasks) => {
            let mut list = Vec::new();
            for t in tasks {
                list.push(LlmllVal::from((
                    t.id,
                    (t.title, (t.completed, (t.priority, (t.created, t.completed_date)))),
                )));
            }
            LlmllVal::List(list)
        }
        Err(_) => LlmllVal::List(vec![]),
    }
}

pub fn stringify_tasks(arg0: LlmllVal) -> LlmllVal {
    if let LlmllVal::List(list) = arg0 {
        let mut tasks = Vec::new();
        for item in list {
            if let LlmllVal::Pair(id_b, rest1) = item {
                if let LlmllVal::Pair(title_b, rest2) = *rest1 {
                    if let LlmllVal::Pair(comp_b, rest3) = *rest2 {
                        if let LlmllVal::Pair(prio_b, rest4) = *rest3 {
                            if let LlmllVal::Pair(cred_b, cdate_b) = *rest4 {
                                tasks.push(TaskData {
                                    id: id_b.as_str().to_string(),
                                    title: title_b.as_str().to_string(),
                                    completed: comp_b.as_bool(),
                                    priority: prio_b.as_int(),
                                    created: cred_b.as_str().to_string(),
                                    completed_date: cdate_b.as_str().to_string(),
                                });
                            }
                        }
                    }
                }
            }
        }
        let json = serde_json::to_string(&tasks).unwrap_or_else(|_| "[]".to_string());
        LlmllVal::from(json)
    } else {
        LlmllVal::from("[]")
    }
}

pub fn parse_task_input(arg0: LlmllVal) -> LlmllVal {
    let json_str = arg0.as_str();
    match serde_json::from_str::<TaskInputData>(json_str) {
        Ok(t) => {
            let val = LlmllVal::from((t.title, (t.completed, t.priority)));
            LlmllVal::Adt("Success".to_string(), vec![val])
        }
        Err(e) => LlmllVal::Adt("Error".to_string(), vec![LlmllVal::from(e.to_string())]),
    }
}
