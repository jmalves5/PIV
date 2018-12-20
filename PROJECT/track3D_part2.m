function [ objects, cam2toW ] = track3D_part2( img_name_seq1, img_name_seq2, cam_params)
addpath('P_all_folder','Part2_folder')
run('vlfeat-0.9.21/toolbox/vl_setup')
vl_version verbose
%Draw plots
plots = 0;

%UBC Match:
match_thresh = 1.5;

% RANSAC:
%Set number of iterations
niter = 100;

%Set error treshold for inliers
error_tresh = 0.2;

img_name_1 = img_name_seq1(15);
img_name_2 = img_name_seq2(15);
[image1, image1_depth] = load_images(img_name_1);
[image2, image2_depth] = load_images(img_name_2);
[image1, xyz1_array, rgbd1] = align_depth_to_rgb(image1_depth,image1,cam_params);
[image2, xyz2_array, rgbd2] = align_depth_to_rgb(image2_depth,image2,cam_params); 

if(plots)
    figure1 = figure();
    imshow(image1);
    figure2 = figure();
    imshow(image2);
end

%Convert to gray scale for SIFT
image1_gray=rgb2gray(image1);
image2_gray=rgb2gray(image2);

% depth_array1 = reshape(image1_depth, [480*640, 1]);
% depth_array2 = reshape(image2_depth, [480*640, 1]);

%Re-shape array into 3 [480x640] matrices:
% - The 1st gives access to x values in world frame
% - The 2nd gives access to y values in world frame
% - The 3rd gives access to z values in world frame
xyz1 = reshape(xyz1_array, [480, 640, 3]);
xyz2 = reshape(xyz2_array, [480, 640, 3]);

if(plots)
    figure_xyz1=figure(4);
    showPointCloud(xyz1);
    figure_xyz2=figure(5);
    showPointCloud(xyz2);
end

%Get image descriptors and positions
[f1, d1] = vl_sift(single(image1_gray));
[f2, d2] = vl_sift(single(image2_gray));

%Match descriptors and score this match from both images with last param.
%being maximum error between matches
[match, ~] = vl_ubcmatch(d1, d2, match_thresh);

%Plot the matches and draw lines between them
if(plots)
    plot_matches( image1, image2, f1, f2, match, 3);
end

% RANSAC:

%Create matrices for RANSAC
xyz1_4points = zeros(4,3);
xyz2_4points = zeros(4,3);

image1_4points = zeros(4, 2);
image2_4points = zeros(4, 2);

n_inliers = zeros(1, niter);

if(plots)
    plot_points1= zeros(niter, 4, 2);
    plot_points2= zeros(niter, 4, 2);
end

%Get xyz of valid matches (i.e z ~=0)
f1_matched = fix(f1(1:2, match(1,:)));
f2_matched = fix(f2(1:2, match(2,:)));

for j = 1:length(f1_matched)
    xyz1_matched(j,:,:) = xyz1(f1_matched(2,j), f1_matched(1,j),:);
    xyz2_matched(j,:,:) = xyz2(f2_matched(2,j), f2_matched(1,j),:);
end

good_inds = find((xyz1_matched(:,3).*xyz2_matched(:,3))~=0);
xyz1_matched = xyz1_matched(good_inds,:);
xyz2_matched = xyz2_matched(good_inds,:);

n_valid_matches = length(xyz1_matched);

%Create matrices for inliers
vector1_inliers = zeros(n_valid_matches, 3, niter);
vector2_inliers = zeros(n_valid_matches, 3, niter);

%Main RANSAC cycle
for i=0:niter-1
    
    %Get 4 random matched points for each iteration
    for j=1:4   
        image1_4points(j) = 0;
        image2_4points(j) = 0;
        xyz1_4points(j) = 0;
        xyz2_4points(j) = 0;
        
        %Guarantee that these matches are valid and unique
        while ismember(0,  xyz1_4points(j)) || ismember(0,  xyz2_4points(j)) || length(unique(xyz2_4points(1:j)))~=j
                      
                random_match = match(:, randperm(length(match), 1));
                
                image1_4points(j, :)=f1(1:2 ,random_match(1));
                image2_4points(j, :)=f2(1:2, random_match(2));
                image1_4points(j, :) = fix(image1_4points(j, :));
                image2_4points(j, :) = fix(image2_4points(j, :));
                
                image1_4points(find(image1_4points(j)) == 0) = 1;
                image2_4points(find(image2_4points(j)) == 0) = 1;
                
                %Get matched points coordinates in 3D
                xyz1_4points(j, :) = xyz1(image1_4points(j, 2), image1_4points(j, 1), :);
                xyz2_4points(j, :) = xyz2(image2_4points(j, 2), image2_4points(j, 1), :);
        end
    end

    if(plots)
        %Save 2D points to plot them later
        plot_points1(i+1, :, 1)=image1_4points(:,1);        
        plot_points1(i+1, :, 2)=image1_4points(:,2);
        plot_points2(i+1, :, 1)=image2_4points(:,1);
        plot_points2(i+1, :, 2)=image2_4points(:,2);
    end
        
    %Calculate model for Rotation and Translation based on 4 random points
    [R, T] = calcR_T_svd(xyz1_4points', xyz2_4points');
    
    %Use Rotation and Translation to project xyz1 into xyz2 frame
    xyz12_matched=R*xyz1_matched' + repmat(T,1,n_valid_matches);

    %Check how many matches are considered inliers with estimated model
    for k = 1:n_valid_matches
        %Use Euclidian norm to calculate estimation error
        err = norm(xyz12_matched(:,k)'-xyz2_matched(k,:));
        
        if (err<error_tresh)
            n_inliers(i+1) = n_inliers(i+1) + 1;
            vector1_inliers(n_inliers(i+1),:,i+1)=xyz1_matched(k,:);
            vector2_inliers(n_inliers(i+1),:,i+1)=xyz2_matched(k,:);
        end
    end    
end

[~, index] = max(n_inliers);

if(plots)
    %Plot the 4 random point pairs used for estimating best projection model
    figure(figure1);
    hold on
    plot(plot_points1(index, :, 1), plot_points1(index, :, 2),'*r');
    hold off
    
    figure(figure2);   
    hold on
    plot(plot_points2(index, :, 1), plot_points2(index, :, 2),'*r');
    hold off
    
    %Plot all 4 random point pairs used for estimating projection models
    figure(6)
    imshow(cat(2, image1,image2));
    hold on;
    for i=1:niter
        plot(plot_points1(i, :, 1), plot_points1(i, :, 2),'*r'); 
        plot(plot_points2(i, :, 1)+size(image1,2), plot_points2(i, :, 2),'*r');
        for j = 1:4
            plot([1 3], [2 4])
            h = line([plot_points1(i, j, 1) ; plot_points2(i, j, 1)+size(image1,2)], [plot_points1(i, j, 2) ; plot_points2(i, j, 2)]) ;
            set(h,'linewidth', 1, 'color', 'r') ;
        end
    end

    hold off
end

%Eliminate zeros from best inliers
final_inliers1=vector1_inliers(:,:, index);
final_inliers2=vector2_inliers(:,:, index);
final_inliers1( all(~final_inliers1,2), : ) = [];
final_inliers2( all(~final_inliers2,2), : ) = [];

%Estimate new model based on all inliers
[final_R, final_T] = calcR_T_svd(final_inliers1', final_inliers2');

%Shift world frame of camera 1 to camera 2 world frame
final_xyz12_array=final_R*xyz1_array' + repmat(final_T,1,length(xyz1_array));

if(plots)
    %Plot point cloud merge
    figure(7)
    showPointCloud(final_xyz12_array');
    pc2=pointCloud(xyz2_array,'Color',reshape(rgbd2,[480*640 3]));
    pc12 = pointCloud(final_xyz12_array','Color',reshape(rgbd1,[480*640 3]));
    showPointCloud(pcmerge(pc12,pc2,0.00001));
    figure;
    showPointCloud(pcdownsample(pcdenoise(pcmerge(pc12,pc2,0.00001)),'gridAverage',0.005));
    drawnow;
end

%%
[objects1]=track3D_part1(img_name_seq1, cam_params);
[objects2]=track3D_part1(img_name_seq2, cam_params);

