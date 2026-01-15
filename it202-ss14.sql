-- chuẩn bị cơ sở dữ liệu
create database if not exists social_network;
use social_network;

-- tạo bảng users (dùng cho bài 1, 2, 3)
create table if not exists users (
    user_id int primary key auto_increment,
    username varchar(50) not null,
    posts_count int default 0,
    following_count int default 0,
    followers_count int default 0
);

-- tạo bảng posts (dùng cho bài 1, 2, 4)
create table if not exists posts (
    post_id int primary key auto_increment,
    user_id int not null,
    content text not null,
    created_at datetime default current_timestamp,
    likes_count int default 0,
    comments_count int default 0,
    foreign key (user_id) references users(user_id)
);

-- thêm dữ liệu mẫu
insert into users (username) values ('nguyen_van_a'), ('tran_thi_b');

---------------------------------------------------------
-- bài 1: đăng bài viết mới
---------------------------------------------------------

-- trường hợp 1: thành công
start transaction;
insert into posts (user_id, content) values (1, 'bài viết đầu tiên của tôi');
update users set posts_count = posts_count + 1 where user_id = 1;
commit;

-- trường hợp 2: lỗi (user_id không tồn tại) -> rollback
start transaction;
insert into posts (user_id, content) values (999, 'bài viết lỗi'); -- lỗi khóa ngoại
-- nếu có lỗi ở lệnh trên, các lệnh sau sẽ không hợp lệ hoặc gây lỗi tiếp
update users set posts_count = posts_count + 1 where user_id = 999;
rollback;

---------------------------------------------------------
-- bài 2: thích (like) bài viết
---------------------------------------------------------

create table if not exists likes (
    like_id int primary key auto_increment,
    post_id int not null,
    user_id int not null,
    unique key unique_like (post_id, user_id),
    foreign key (post_id) references posts(post_id),
    foreign key (user_id) references users(user_id)
);

-- kịch bản like
start transaction;
insert into likes (post_id, user_id) values (1, 2);
update posts set likes_count = likes_count + 1 where post_id = 1;
commit;

-- thử nghiệm like lần 2 (gây lỗi unique key)
start transaction;
insert into likes (post_id, user_id) values (1, 2); -- lệnh này sẽ báo lỗi
-- khi lỗi xảy ra, bạn cần thực hiện rollback
rollback;

---------------------------------------------------------
-- bài 3: theo dõi (follow) người dùng
---------------------------------------------------------

create table if not exists followers (
    follower_id int not null,
    followed_id int not null,
    primary key (follower_id, followed_id),
    foreign key (follower_id) references users(user_id),
    foreign key (followed_id) references users(user_id)
);

delimiter //
create procedure sp_follow_user(in p_follower_id int, in p_followed_id int)
begin
    declare v_check_exist int;
    
    -- xử lý lỗi hệ thống
    declare exit handler for sqlexception 
    begin
        rollback;
    end;

    start transaction;
    
    -- 1. kiểm tra user tồn tại
    select count(*) into v_check_exist from users where user_id in (p_follower_id, p_followed_id);
    
    -- 2. kiểm tra không tự follow mình và chưa follow trước đó
    if v_check_exist = 2 and p_follower_id <> p_followed_id then
        insert into followers (follower_id, followed_id) values (p_follower_id, p_followed_id);
        
        -- 3. cập nhật các chỉ số count
        update users set following_count = following_count + 1 where user_id = p_follower_id;
        update users set followers_count = followers_count + 1 where user_id = p_followed_id;
        
        commit;
    else
        rollback;
    end if;
end //
delimiter ;

-- gọi thử:
call sp_follow_user(1, 2);

---------------------------------------------------------
-- bài 4: đăng bình luận kèm savepoint
---------------------------------------------------------

create table if not exists comments (
    comment_id int primary key auto_increment,
    post_id int not null,
    user_id int not null,
    content text not null,
    created_at datetime default current_timestamp,
    foreign key (post_id) references posts(post_id),
    foreign key (user_id) references users(user_id)
);

delimiter //
create procedure sp_post_comment(in p_post_id int, in p_user_id int, in p_content text)
begin
    -- nếu gặp lỗi ở bước update thì chỉ rollback về sau bước insert
    declare continue handler for sqlexception 
    begin
        rollback to after_insert;
        -- sau khi rollback về savepoint, ta có thể kết thúc hoặc xử lý tiếp
        commit; 
    end;

    start transaction;
    
    -- bước 1: insert bình luận
    insert into comments (post_id, user_id, content) values (p_post_id, p_user_id, p_content);
    
    -- thiết lập điểm lưu (savepoint)
    savepoint after_insert;
    
    -- bước 2: update số lượng (giả sử có thể gây lỗi)
    update posts set comments_count = comments_count + 1 where post_id = p_post_id;
    
    commit;
end //
delimiter ;

-- gọi thử thành công:
call sp_post_comment(1, 2, 'bài viết hay quá!');

-- tiếp tục sử dụng csdl social_network
use social_network;

---------------------------------------------------------
-- bài 5: xóa bài viết và nội dung liên quan
---------------------------------------------------------

-- 1. tạo bảng delete_log để ghi lịch sử xóa
create table if not exists delete_log (
    log_id int primary key auto_increment,
    post_id int not null,
    deleted_at datetime default current_timestamp,
    deleted_by int not null
);

delimiter //
create procedure sp_delete_post(in p_post_id int, in p_user_id int)
begin
    declare v_post_exists int;
    
    -- xử lý lỗi hệ thống: nếu bất kỳ lệnh nào lỗi, thực hiện rollback ngay
    declare exit handler for sqlexception 
    begin
        rollback;
    end;

    start transaction;

    -- 1. kiểm tra bài viết có tồn tại và có thuộc về user này không
    select count(*) into v_post_exists 
    from posts 
    where post_id = p_post_id and user_id = p_user_id;

    if v_post_exists > 0 then
        -- 2. xóa các dữ liệu liên quan trong bảng likes
        delete from likes where post_id = p_post_id;

        -- 3. xóa các dữ liệu liên quan trong bảng comments
        delete from comments where post_id = p_post_id;

        -- 4. xóa bài viết gốc trong bảng posts
        delete from posts where post_id = p_post_id;

        -- 5. giảm số lượng bài viết của user (posts_count)
        update users set posts_count = posts_count - 1 where user_id = p_user_id;

        -- 6. ghi log vào bảng delete_log
        insert into delete_log (post_id, deleted_by) values (p_post_id, p_user_id);

        -- hoàn tất giao dịch
        commit;
    else
        -- bài viết không tồn tại hoặc không đủ quyền xóa
        rollback;
    end if;
end //
delimiter ;

---------------------------------------------------------
-- chạy thử nghiệm các trường hợp
---------------------------------------------------------

-- trường hợp 1: xóa hợp lệ (user 1 xóa bài viết của mình)
-- giả sử bài viết id = 1 là của user_id = 1
call sp_delete_post(1, 1);

-- trường hợp 2: xóa không hợp lệ (user 2 cố tình xóa bài của user 1)
-- giả sử bài viết id = 2 là của user_id = 1, nhưng truyền vào p_user_id = 2
call sp_delete_post(2, 2);

-- trường hợp 3: xóa bài viết không tồn tại
call sp_delete_post(999, 1);

-- kiểm tra kết quả sau khi xóa
select * from delete_log;
select * from users;
