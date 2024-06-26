#!/usr/bin/env ts-node

import { config } from 'dotenv';
import { execSync } from 'child_process';
import * as fs from 'fs';
import * as readline from 'readline';

// Load environment variables from .env file
config();

function askCommitMessage(): Promise<string> {
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout,
    });

    return new Promise((resolve) => {
        rl.question('Enter commit message (leave empty for "Initial Commit"): ', (answer) => {
            rl.close();
            resolve(answer || 'Initial Commit');
        });
    });
}

async function gitclean() {
    const odir = process.cwd();
    const temp = fs.mkdtempSync('git.');
    const cleanup = () => {
        fs.rmSync(temp, { recursive: true, force: true });
    };
    process.on('exit', cleanup);
    
    process.chdir(temp);
    const URL = process.env.GITURL!.replace(/https:\/\/([^@]*@)?/, '');

    
    execSync(`git clone "https://${process.env.USERNAME}:${process.env.PASSWORD}@${URL}"`);
    process.chdir(URL.substring(URL.lastIndexOf('/') + 1, URL.lastIndexOf('.git')));
    
    const branches = process.env.BRANCHES!.split(',');
    for (const BR of branches) {
        try {
            execSync(`git ls-remote --heads origin ${BR}`);
            try {
                execSync(`git show-ref --verify --quiet refs/heads/${BR}`);
                console.log(`Working on branch ${BR}`);
                execSync(`git checkout ${BR}`);
                execSync(`git checkout --orphan "temp-${BR}"`);
                execSync('git add -A');
                const commit_msg = process.env.commit_msg || await askCommitMessage();
                execSync(`git commit -m "${commit_msg}"`);
                execSync(`git branch -D ${BR}`);
                execSync(`git branch -m ${BR}`);
                execSync(`git push -f origin ${BR}`);
                execSync('git gc --aggressive --prune=all');
            } catch (error) {
                console.error(`Error: Branch ${BR} does not exist locally.`);
                process.exit(1);
            }
        } catch (error) {
            console.error(`Error: Branch ${BR} does not exist in remote.`);
            process.exit(1);
        }
    }
    
    process.chdir(odir);
    cleanup();
}

gitclean();
  
